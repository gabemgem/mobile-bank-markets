import org.nlogo.headless.HeadlessWorkspace;

/** Loads a generated library in an isolated model copy and exercises the ABM. */
public class GeneratedLibraryChecks {
    public static void main(String[] args) throws Exception {
        HeadlessWorkspace workspace = HeadlessWorkspace.newInstance();
        try {
            workspace.open(args[0]);
            workspace.command("initialize-controls set network-source \"Imported synthetic\" " +
                "set selected-market \"synthetic-00001\"");
            for (String policy : new String[]{"No sharing", "Network sharing", "All-to-all sharing"}) {
                workspace.command("set sharing-mode \"" + policy + "\" setup");
                String expected = "count kiosks = " + Integer.parseInt(args[1]) +
                    " and count relationships = " + Integer.parseInt(args[2]) +
                    " and count kiosks with [count relationship-neighbors = 0] = " + Integer.parseInt(args[3]);
                if (!Boolean.TRUE.equals(workspace.report(expected)))
                    throw new AssertionError("Generated graph counts changed during import");
                workspace.command("repeat 10 [go] check-accounting");
            }
            System.out.println("PASS: uncertainty-generated graph imported with correct nodes, ties, and isolates; all sharing policies passed accounting.");
        } finally { workspace.dispose(); }
        System.exit(0);
    }
}
