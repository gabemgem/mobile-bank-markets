import org.nlogo.headless.HeadlessWorkspace;
import org.nlogo.core.LogoList;
import java.util.*;

/** Verify every exported adjacency and exercise both generators in the ABM. */
public class SyntheticLibraryChecks {
    static String quoted(String s) { return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""; }
    static String key(String a, String b) { return a.compareTo(b) < 0 ? a + "|" + b : b + "|" + a; }
    static int column(LogoList header, String name) {
        for (int i=0; i<header.size(); i++) if (name.equals(header.apply(i))) return i;
        throw new AssertionError("Missing catalog column: " + name);
    }
    static void check(HeadlessWorkspace w, String expression) throws Exception {
        if (!Boolean.TRUE.equals(w.report(expression))) throw new AssertionError(expression);
    }
    public static void main(String[] args) throws Exception {
        long started = System.nanoTime();
        HeadlessWorkspace w = HeadlessWorkspace.newInstance();
        try {
            w.open(args[0]);
            w.command("initialize-controls set network-source \"Imported synthetic\"");
            LogoList catalog = (LogoList)w.report("local-catalog");
            LogoList header = (LogoList)w.report("first network-cache-catalog");
            int nc=column(header,"n_nodes"), ec=column(header,"n_links"), ic=column(header,"n_isolates");
            int mc=column(header,"max_degree"), gc=column(header,"generator");
            for (String generator:new String[]{"pooled","corrected_hub"})
                check(w,"(length filter [row -> (item " + gc + " row) = " + quoted(generator) +
                    " and (word (item " + nc + " row) \"\") = \"12\"] local-catalog) = 20");
            Map<String, Set<String>> expected = new HashMap<>();
            LogoList edges = (LogoList)w.report("network-cache-edges");
            for (int i=0; i<edges.size(); i++) {
                LogoList edge=(LogoList)edges.apply(i);
                expected.computeIfAbsent((String)edge.apply(0), k -> new HashSet<>())
                    .add(key((String)edge.apply(1),(String)edge.apply(2)));
            }
            Set<String> cells = new HashSet<>();
            for (int i=0; i<catalog.size(); i++) {
                LogoList row=(LogoList)catalog.apply(i); String id=(String)row.apply(0);
                int n=((Number)row.apply(nc)).intValue(), e=((Number)row.apply(ec)).intValue();
                int isolates=((Number)row.apply(ic)).intValue(), maximum=((Number)row.apply(mc)).intValue();
                w.command("set selected-market " + quoted(id) + " set sharing-mode \"Network sharing\" setup");
                check(w,"count kiosks = " + n + " and count relationships = " + e +
                    " and count kiosks with [count relationship-neighbors = 0] = " + isolates +
                    " and max [count relationship-neighbors] of kiosks = " + maximum);
                LogoList actual=(LogoList)w.report("[(list [agent-id] of end1 [agent-id] of end2)] of relationships");
                Set<String> keys=new HashSet<>();
                for (int j=0; j<actual.size(); j++) {
                    LogoList edge=(LogoList)actual.apply(j);
                    keys.add(key((String)edge.apply(0),(String)edge.apply(1)));
                }
                if (!keys.equals(expected.getOrDefault(id, Collections.emptySet())))
                    throw new AssertionError("Adjacency changed: " + id);
                w.command("repeat 3 [go] check-accounting");
                if (n==2 || n==13 || n==24) {
                    String cell=row.apply(gc)+":"+n;
                    if (cells.add(cell)) for (String policy:new String[]{"No sharing","Network sharing","All-to-all sharing"})
                        w.command("set sharing-mode " + quoted(policy) + " setup repeat 10 [go] check-accounting");
                }
            }
            if (catalog.size()!=920 || cells.size()!=6) throw new AssertionError("Incomplete generated ensemble.");
            w.command("set network-source \"Synthetic random\" setup go check-accounting");
            check(w,"network-cache-source = \"\" and empty? network-cache-nodes");
            System.out.printf("PASS: all %d graphs imported with exact adjacencies/counts/isolates; " +
                "all policies at sizes 2/13/24 for both generators; random-mode cache clearing (%.1f s).%n",
                catalog.size(),(System.nanoTime()-started)/1e9);
        } finally { w.dispose(); }
        System.exit(0);
    }
}
