import org.nlogo.headless.HeadlessWorkspace;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicInteger;

/** Real HTTP fixtures plus callback races, with no survey data or GitHub writes. */
public class WebNetworkChecks {
    static final String C="network_id,network_type\nfixture,synthetic-handcrafted\n";
    static final String N="network_id,node_id\nfixture,a\nfixture,b\nfixture,c\nfixture,d\n";
    static final String E="network_id,source,target\nfixture,a,b\n";
    static HeadlessWorkspace w;
    static String q(String s) {return "\""+s.replace("\\","\\\\").replace("\"","\\\"").replace("\n","\\n")+"\"";}
    static void cmd(String s) throws Exception {w.command(s);}
    static void check(String s) throws Exception {if(!Boolean.TRUE.equals(w.report(s))) throw new AssertionError(s);}
    static void refused(String s) throws Exception {
        boolean refused=false;try {cmd(s);} catch(Exception expected) {refused=true;}
        if(!refused) throw new AssertionError("Should refuse: "+s);
    }
    static void receive(String token,int index,String data) throws Exception {
        cmd("receive-network-file "+token+" "+index+" "+q(data));
    }
    public static void main(String[] args) throws Exception {
        AtomicInteger requests=new AtomicInteger();
        HttpServer server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
        server.createContext("/",exchange -> {
            requests.incrementAndGet();String path=exchange.getRequestURI().getPath();
            String text=path.endsWith("networks.csv")?C:path.endsWith("nodes.csv")?N:E;
            int status=path.startsWith("/missing/")?404:200;
            if(path.startsWith("/bad/")) text="wrong,header\nhtml,error\n";
            if(path.startsWith("/orphan/") && path.endsWith("edges.csv")) text=E+"fixture,a,unknown\n";
            if(path.startsWith("/isolated/") && path.endsWith("edges.csv")) text="network_id,source,target\n";
            byte[] bytes=text.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type","text/csv; charset=utf-8");
            exchange.sendResponseHeaders(status,bytes.length);exchange.getResponseBody().write(bytes);exchange.close();
        });server.start();
        String base="http://127.0.0.1:"+server.getAddress().getPort();
        w=HeadlessWorkspace.newInstance();
        try {
            w.open(args[0]);cmd("initialize-controls setup repeat 3 [go]");
            if(requests.get()!=0) throw new AssertionError("Random mode requested HTTP");
            cmd("set github-network-base-url "+q(base+"/valid/")+" set selected-market \"fixture\" load-github-networks");
            check("position \"Ready:\" network-library-status = 0 and length local-catalog = 1");
            for(String policy:new String[]{"No sharing","Network sharing","All-to-all sharing"}) {
                cmd("set sharing-mode "+q(policy)+" setup repeat 10 [go] check-accounting");
                check("count kiosks = 4 and count relationships = 1 and count kiosks with [count relationship-neighbors = 0] = 2");
                check("network-cache-source = github-network-base-url");
            }
            cmd("begin-github-load "+q(base+"/valid")+" let old-token network-load-token " +
                "receive-network-file old-token 0 "+q(C));
            check("network-load-status = \"Loading\" and empty? network-cache-catalog");
            refused("setup");refused("go");
            cmd("let old-token network-load-token cancel-network-load receive-network-file old-token 1 "+q(N));
            check("empty? network-cache-nodes and empty? network-cache-catalog");
            cmd("begin-github-load "+q(base+"/valid")+" let old-token network-load-token begin-github-load "+q(base+"/other")+
                " receive-network-file old-token 0 "+q(C)+" fail-network-load old-token \"late failure\"");
            check("network-load-status = \"Loading\" and item 0 network-pending-tables = []");
            receive("network-load-token",2,E);receive("network-load-token",0,C);
            check("empty? network-cache-catalog");receive("network-load-token",1,N);
            check("position \"Ready:\" network-library-status = 0");
            cmd("begin-github-load "+q(base+"/valid")+" set network-load-timeout 0");
            check("position \"Error:\" network-library-status = 0");
            receive("network-load-token",0,C);check("empty? network-cache-catalog");
            cmd("set network-load-timeout 30");
            for(String bad:new String[]{"bad","missing","orphan"}) {
                cmd("set github-network-base-url "+q(base+"/"+bad)+" load-github-networks");
                check("position \"Error:\" network-library-status = 0 and empty? network-cache-catalog");refused("setup");
            }
            cmd("set github-network-base-url "+q(base+"/isolated")+" load-github-networks set selected-market \"fixture\" setup go check-accounting");
            check("count kiosks = 4 and count relationships = 0");
            cmd("begin-github-load "+q(base+"/valid")+" let old-token network-load-token use-random-networks setup " +
                "receive-network-file old-token 0 "+q(C)+" repeat 3 [go] check-accounting");
            check("network-source = \"Synthetic random\" and empty? network-cache-catalog");
            System.out.println("PASS: HTTP load, three policies, atomic cache, blocked partial Setup/Go, stale/reordered callbacks, " +
                "cancellation, timeout, malformed/orphan/404 errors, empty edge file, retry and random-mode recovery.");
        } finally {w.dispose();server.stop(0);}
        System.exit(0);
    }
}
