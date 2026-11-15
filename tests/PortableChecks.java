import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import org.nlogo.headless.HeadlessWorkspace;

/** Uses an isolated model copy: no survey file is read or moved. */
public class PortableChecks {
    static void check(HeadlessWorkspace w, String expression) throws Exception {
        if (!Boolean.TRUE.equals(w.report(expression))) throw new AssertionError(expression);
    }
    static void write(Path folder, String name, String contents) throws Exception {
        Files.write(folder.resolve(name), contents.getBytes(StandardCharsets.UTF_8));
    }
    public static void main(String[] args) throws Exception {
        Path directory = Files.createTempDirectory("netlogo-data-free-");
        Path model = directory.resolve("MobileBankMarkets.nlogox");
        Files.copy(Paths.get(args[0]), model);
        org.w3c.dom.Document bindings = javax.xml.parsers.DocumentBuilderFactory.newInstance()
            .newDocumentBuilder().parse(model.toFile());
        org.w3c.dom.NodeList all = bindings.getElementsByTagName("widgets").item(0).getChildNodes();
        for (int i=0; i<all.getLength(); i++) {
            if (!(all.item(i) instanceof org.w3c.dom.Element)) continue;
            org.w3c.dom.Element widget = (org.w3c.dom.Element)all.item(i);
            // Desktop widgets bind display; headless widgets bind variable.
            if (widget.hasAttribute("variable") &&
                    !widget.getAttribute("display").equals(widget.getAttribute("variable")))
                throw new AssertionError("Desktop/headless widget name mismatch: " + widget.getAttribute("variable"));
        }
        HeadlessWorkspace w = HeadlessWorkspace.newInstance();
        try {
            w.open(model.toString());
            // Includes the NETWORK-SOURCE regression: startup/setup work without its chooser.
            w.command("setup repeat 10 [go] check-accounting");
            check(w,"network-source = \"Synthetic random\" and count kiosks = number-of-kiosks");
            check(w,"not file-exists? \"data\" and not file-exists? \"synthetic-networks\"");
            w.command("set network-source \"Observed mutual willingness\"");
            boolean refused = false;
            try { w.command("setup"); } catch (Exception expected) { refused = true; }
            if (!refused) throw new AssertionError("Missing observed data silently accepted");
            w.command("set network-source \"Synthetic random\" setup go");
            w.command("set ui-target-balance-percent 60 set ui-low-balance-percent 15 interface-setup");
            check(w,"target-balance-percent = 60 and low-balance-percent = 15");
            w.command("set target-balance-percent 40 setup go");
            check(w,"target-balance-percent = 40");
            Path generated = Files.createDirectory(directory.resolve("synthetic-networks"));
            write(generated,"networks.csv","network_id,network_type,n_nodes,n_links,n_isolates\nfixture,synthetic-handcrafted,4,1,2\n");
            write(generated,"nodes.csv","network_id,node_id\nfixture,node-a\nfixture,node-b\nfixture,node-c\nfixture,node-d\n");
            write(generated,"edges.csv","network_id,source,target\nfixture,node-a,node-b\n");
            w.command("set network-source \"Imported synthetic\" set selected-market \"\" setup");
            check(w,"count kiosks = 4 and count relationships = 1 and active-market = \"fixture\"");
            check(w,"count kiosks with [count relationship-neighbors = 0] = 2");
            check(w,"network-description = \"synthetic-handcrafted: fixture\"");
            w.command("repeat 10 [go] check-accounting");
            System.out.println("PASS: data-free startup, explicit network-source global, missing-data error, "
                + "abstract-mode recovery, and pre-generated synthetic import with isolates.");
        } finally { w.dispose(); }
        // Strip every parameter widget: the core must still compile and run.
        org.w3c.dom.Document document = javax.xml.parsers.DocumentBuilderFactory.newInstance()
            .newDocumentBuilder().parse(model.toFile());
        org.w3c.dom.Node widgets = document.getElementsByTagName("widgets").item(0);
        for (int i = widgets.getChildNodes().getLength()-1; i >= 0; i--) {
            org.w3c.dom.Node child = widgets.getChildNodes().item(i);
            if (child instanceof org.w3c.dom.Element && ((org.w3c.dom.Element)child).hasAttribute("variable"))
                widgets.removeChild(child);
        }
        Path coreModel = directory.resolve("CodeOnly.nlogox");
        javax.xml.transform.TransformerFactory.newInstance().newTransformer().transform(
            new javax.xml.transform.dom.DOMSource(document),
            new javax.xml.transform.stream.StreamResult(coreModel.toFile()));
        HeadlessWorkspace core = HeadlessWorkspace.newInstance();
        try {
            core.open(coreModel.toString());
            core.command("setup repeat 5 [go] check-accounting");
            check(core,"target-balance-percent = 50 and low-balance-percent = 25 and settlement-delay = 1");
            core.command("set target-balance-percent 60 setup go");
            check(core,"target-balance-percent = 60");
            System.out.println("PASS: compiled and ran with every parameter widget removed.");
        } finally { core.dispose(); }
        System.exit(0);
    }
}
