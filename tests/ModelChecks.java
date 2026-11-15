import org.nlogo.headless.HeadlessWorkspace;

/** Headless regression checks. See run-checks.ps1 for the local entry point. */
public class ModelChecks {
    private static HeadlessWorkspace model;
    private static void command(String source) throws Exception { model.command(source); }
    private static Object report(String source) throws Exception { return model.report(source); }
    private static void check(String condition) throws Exception {
        if (!Boolean.TRUE.equals(report(condition))) throw new AssertionError(condition);
    }
    private static void defaults() throws Exception {
        command("initialize-controls set network-source \"Synthetic random\" set number-of-kiosks 20 set starting-balance 500 "
            + "set network-density 0.2 set participation-percent 100 "
            + "set requests-per-tick 40 set maximum-request 100 "
            + "set withdrawal-share 0.5 set demand-polarization 0.35 "
            + "set minimum-reserve 100 set model-seed 42 "
            + "set low-balance-percent 25 set target-balance-percent 50 "
            + "set settlement-delay 1 set show-balances? false");
    }
    private static Object run(String mode, int delay) throws Exception {
        command("set sharing-mode \"" + mode + "\" set settlement-delay " + delay
            + " setup repeat 100 [go]");
        check("requested-count = 4000 and sum served-values <= sum requested-values");
        check("initiated-count - settled-count = count transfers");
        check("all? kiosks [available true >= -0.000001 and available false >= -0.000001]");
        command("check-accounting");
        System.out.println(mode + ", delay " + delay + ": "
            + report("(list (percent-served -1) initiated-count settled-count count transfers)"));
        return report("(list requested-values served-values initiated-count settled-count "
            + "sort [cash] of kiosks sort [efloat] of kiosks)");
    }
    private static void fixture(int delay, boolean needsCash) throws Exception {
        defaults();
        command("set number-of-kiosks 4 set network-density 1 set requests-per-tick 0 "
            + "set sharing-mode \"Network sharing\" set settlement-delay " + delay + " setup "
            + "ask kiosks [set cash " + (needsCash ? "700" : "300")
            + " set efloat " + (needsCash ? "300" : "700") + "] "
            + "ask kiosk 0 [set cash " + (needsCash ? "100" : "900")
            + " set efloat " + (needsCash ? "900" : "100") + "] "
            + "set initial-cash sum [cash] of kiosks set initial-efloat sum [efloat] of kiosks");
    }
    public static void main(String[] args) throws Exception {
        model = HeadlessWorkspace.newInstance();
        try {
            model.open(args[0]);
            defaults();
            Object reference = null;
            for (String mode : new String[]{"No sharing", "Network sharing", "All-to-all sharing"}) {
                for (int delay = 0; delay <= 2; delay++) {
                    run(mode, delay);
                    if (reference == null) reference = report("requested-values");
                    if (!reference.equals(report("requested-values"))) throw new AssertionError("Demand changed");
                    if (mode.equals("No sharing")) check("initiated-count = 0 and count transfers = 0");
                    else check("initiated-count > 0 and settled-count > 0");
                }
            }
            Object repeat = run("Network sharing", 1);
            if (!repeat.equals(run("Network sharing", 1))) throw new AssertionError("Not reproducible");
            command("set network-density 0");
            run("Network sharing", 1);
            check("initiated-count = 0 and count relationships = 0");
            if (!reference.equals(report("requested-values"))) throw new AssertionError("Topology changed demand");
            command("set participation-percent 0");
            run("All-to-all sharing", 1);
            check("initiated-count = 0");

            // Rebalancing is proactive, even when there are no customer requests.
            fixture(0, true);
            command("go");
            check("requested-count = 0 and initiated-count = 1 and settled-count = 1");
            check("[cash] of kiosk 0 = 500 and [efloat] of kiosk 0 = 500 and count transfers = 0");

            // The same locked trade remains pending for exactly d customer batches.
            for (int delay = 1; delay <= 2; delay++) {
                fixture(delay, true);
                command("go");
                check("initiated-count = 1 and settled-count = 0 and count transfers = 1");
                check("[cash] of kiosk 0 = 100 and [efloat] of kiosk 0 = 900");
                check("[reserved-efloat] of kiosk 0 = 400 and sum [reserved-cash] of kiosks = 400");
                check("all? transfers [due-tick = " + delay + "]");
                command("ask kiosk 0 [serve-request 150 true serve-request 501 false]");
                check("served-count = 0 and initiated-count = 1");
                command("with-local-randomness [ask kiosks [rebalance]] check-accounting");
                check("count transfers = 1");
                if (delay == 2) {
                    command("go");
                    check("settled-count = 0 and count transfers = 1 and [cash] of kiosk 0 = 100");
                }
                command("go");
                check("settled-count = 1 and count transfers = 0");
                check("sum [reserved-cash] of kiosks = 0 and sum [reserved-efloat] of kiosks = 0");
                command("ask kiosk 0 [serve-request 150 true] check-accounting");
                check("served-count = 1 and [cash] of kiosk 0 = 350");
            }

            // E-float shortages use the same trading rule and reserve the cash leg.
            fixture(1, false);
            command("go");
            check("[reserved-cash] of kiosk 0 = 400 and sum [reserved-efloat] of kiosks = 400");
            command("go check-accounting");
            check("[cash] of kiosk 0 = 500 and [efloat] of kiosk 0 = 500 and settled-count = 1");

            // No transaction-triggered rescue; no booking exactly at the threshold.
            fixture(0, true);
            command("ask kiosk 0 [serve-request 150 true]");
            check("served-count = 0 and initiated-count = 0");
            command("setup ask kiosk 0 [set cash 250 set efloat 750] "
                + "set initial-cash sum [cash] of kiosks set initial-efloat sum [efloat] of kiosks go");
            check("initiated-count = 0");

            // Partial refill and both outgoing reserve constraints.
            fixture(1, true);
            command("set minimum-reserve 650 go");
            check("initiated-count = 1 and sum [quantity] of transfers = 50");
            command("ask transfers [let needs-cash cash-needed? "
                + "if [available needs-cash] of partner < minimum-reserve or "
                + "[available (not needs-cash)] of requester < minimum-reserve "
                + "[error \"Outgoing reserve violated\"]]");
            fixture(1, true);
            command("set minimum-reserve 950 go");
            check("initiated-count = 0 and unmet-attempts = 1");

            // Matching cannot allocate a kiosk to two new trades in the same tick.
            fixture(2, true);
            command("ask kiosk 1 [set cash 100 set efloat 900] "
                + "set initial-cash sum [cash] of kiosks set initial-efloat sum [efloat] of kiosks go");
            command("ask kiosks [let outlet self "
                + "if count transfers with [requester = outlet or partner = outlet] > 1 "
                + "[error \"Multiple pending trades\"]]");

            // Trigger and target affect the refill; zero trigger disables trading.
            fixture(0, true);
            command("set low-balance-percent 5 go");
            check("initiated-count = 0");
            fixture(0, true);
            command("set target-balance-percent 40 go");
            check("[cash] of kiosk 0 = 400 and settled-value = 300");
            defaults();
            command("set sharing-mode \"All-to-all sharing\" set low-balance-percent 0 setup repeat 100 [go]");
            check("initiated-count = 0");
            command("set target-balance-percent low-balance-percent");
            boolean rejected = false;
            try { command("validate-controls"); } catch (Exception expected) { rejected = true; }
            if (!rejected) throw new AssertionError("Invalid target accepted");

            for (int delay = 0; delay <= 2; delay++) {
                defaults();
                command("set settlement-delay " + delay + " set number-of-kiosks 60 "
                    + "set starting-balance 100 set maximum-request 250 set minimum-reserve 0 "
                    + "set sharing-mode \"All-to-all sharing\" setup repeat 300 [go] check-accounting");
                check("requested-count = 12000");
            }
            defaults();
            if (Boolean.TRUE.equals(report("file-exists? \"data/networks.csv\""))) {
            org.nlogo.core.LogoList catalog = (org.nlogo.core.LogoList)
                report("but-first csv:from-file \"data/networks.csv\"");
            for (Object entry : catalog.toJava()) {
                org.nlogo.core.LogoList row = (org.nlogo.core.LogoList) entry;
                String market = row.get(0).toString();
                int nodes = ((Number) row.get(2)).intValue();
                int links = ((Number) row.get(3)).intValue();
                int isolates = ((Number) row.get(4)).intValue();
                command("set network-source \"Observed mutual willingness\" set selected-market \""
                    + market + "\" setup");
                check("count kiosks = " + nodes + " and count relationships = " + links);
                check("count kiosks with [count relationship-neighbors = 0] = " + isolates);
                command("repeat 2 [go] check-accounting");
            }
            org.nlogo.core.LogoList first = (org.nlogo.core.LogoList) catalog.get(0);
            command("set selected-market \"" + first.get(0) + "\" setup");
            String demandSignature = "map [r -> (list ([agent-id] of (item 0 r)) (item 1 r) (item 2 r))] customer-requests";
            Object observedDemand = report(demandSignature);
            command("set number-of-kiosks 60 set network-density 1 setup");
            check("count kiosks = " + first.get(2) + " and count relationships = " + first.get(3));
            if (!observedDemand.equals(report(demandSignature))) throw new AssertionError("Ignored controls changed observed demand");
            } else {
                System.out.println("No private data: optional observed-network checks skipped.");
            }
            command("set network-source \"Synthetic random\" set network-density 0 setup");
            check("count kiosks = 60 and count relationships = 0");
            if (args.length > 1) {
                defaults();
                command("set sharing-mode \"Network sharing\" set settlement-delay 2 setup repeat 30 [go]");
                String output = new java.io.File(args[1]).getAbsolutePath().replace('\\', '/');
                command("export-view \"" + output + ".png\" export-all-plots \"" + output + ".csv\"");
            }
            System.out.println("PASS: all scenarios and delays, paired demand, proactive triggers, "
                + "exact settlement timing, locked funds, reserve caps, partial refill, matching, "
                + "thresholds and targets, accounting, repeatability, stress checks, and available local networks.");
        } finally { model.dispose(); }
        System.exit(0);
    }
}
