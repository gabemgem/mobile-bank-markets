import java.util.*;
import org.nlogo.headless.HeadlessWorkspace;

/** Deterministic external rebalancing and demand checks for v2. */
public class V2Checks {
    static HeadlessWorkspace w;
    static void cmd(String code) throws Exception { w.command(code); }
    static void check(String expression) throws Exception {
        if (!Boolean.TRUE.equals(w.report(expression))) throw new AssertionError(expression);
    }
    static void fixture() throws Exception {
        cmd("initialize-controls set commission-percent 0 set number-of-kiosks 4 set network-density 0 set requests-per-tick 0 "
            + "set external-mode \"External only\" set external-open-ticks 12 setup "
            + "ask kiosks [set cash 500 set efloat 500] ask kiosk 0 [set cash 100 set efloat 900] "
            + "set initial-cash sum [cash] of kiosks set initial-efloat sum [efloat] of kiosks");
    }
    public static void main(String[] args) throws Exception {
        w = HeadlessWorkspace.newInstance();
        try {
            w.open(args[1]);
            fixture();
            cmd("set external-travel-ticks 2 set external-service-delay 1 go");
            check("external-started = 1 and external-settled = 0 and count transfers = 1");
            check("sum [reserved-cash] of kiosks = 0 and sum [reserved-efloat] of kiosks = 400");
            cmd("ask kiosk 0 [serve-request 10 true]");
            check("closure-failed-count = 1 and closure-failed-value = 10 and cash-failed-count = 0");
            cmd("repeat 2 [go]");
            check("ticks = 3 and external-settled = 0 and [cash] of kiosk 0 = 100");
            cmd("go check-accounting");
            check("external-settled = 1 and external-value = 400 and net-external-cash = 400");
            check("[cash] of kiosk 0 = 500 and [efloat] of kiosk 0 = 500 and not [away?] of kiosk 0");
            check("closed-kiosk-ticks = 3 and sum [reserved-efloat] of kiosks = 0");

            fixture();
            cmd("set external-travel-ticks 0 set external-service-delay 0 go check-accounting");
            check("external-settled = 1 and count transfers = 0 and closed-kiosk-ticks = 0");
            fixture();
            cmd("set travel-closes-shop? false go ask kiosk 0 [serve-request 10 true] check-accounting");
            check("served-count = 1 and closure-failed-count = 0 and [pending-transfer] of kiosk 0 != nobody");
            cmd("ask kiosk 0 [serve-request 600 false] check-accounting");
            check("efloat-failed-count = 1");

            fixture();
            cmd("set external-open-ticks 0 go");
            check("external-started = 0");
            cmd("set external-open-ticks 1 set external-cycle-ticks 3 go go go");
            check("external-started = 1 and ticks = 4");
            cmd("set external-open-ticks 0 repeat 4 [go] check-accounting");
            check("external-settled = 1");
            fixture();
            cmd("ask kiosks [set external-access? false] go");
            check("external-started = 0");
            fixture();
            cmd("set external-max-amount 75 set external-travel-ticks 0 set external-service-delay 0 go");
            check("external-value = 75 and [cash] of kiosk 0 = 175");
            fixture();
            cmd("set minimum-reserve 900 go");
            check("external-started = 0");
            fixture();
            cmd("ask kiosk 0 [set cash 900 set efloat 100] "
                + "set initial-cash sum [cash] of kiosks set initial-efloat sum [efloat] of kiosks "
                + "set external-travel-ticks 0 set external-service-delay 0 go check-accounting");
            check("net-external-cash = -400 and [cash] of kiosk 0 = 500 and [efloat] of kiosk 0 = 500");

            fixture();
            cmd("set external-mode \"Peers then external\" set sharing-mode \"No sharing\" "
                + "set external-travel-ticks 0 set external-service-delay 0 go check-accounting");
            check("initiated-count = 0 and external-settled = 1");
            fixture();
            cmd("ask kiosk 0 [create-relationship-with kiosk 1] go check-accounting");
            check("initiated-count = 0 and external-started = 1");

            fixture();
            cmd("set external-mode \"Peers then external\" set sharing-mode \"Network sharing\" "
                + "ask kiosk 0 [create-relationship-with kiosk 1] ask kiosk 1 [set cash 900 set efloat 100] "
                + "set initial-cash sum [cash] of kiosks set initial-efloat sum [efloat] of kiosks "
                + "ask kiosk 0 [setxy -14 -14] ask kiosk 1 [setxy 1 -14] go check-accounting");
            check("initiated-count = 1 and external-started = 0 and closed-kiosk-ticks = 1");
            cmd("go");
            check("count kiosks with [away?] = 1 and count transfers = 1 and settled-count = 0");
            cmd("go go check-accounting");
            check("settled-count = 1 and closed-kiosk-ticks = 3");

            cmd("initialize-controls setup");
            check("abs (mean [demand-weight] of kiosks - 1) < 0.000001");
            check("abs (sum [demand-weight * size-factor] of kiosks / count kiosks - 1) < 0.000001");
            check("max [demand-weight] of kiosks > min [demand-weight] of kiosks");
            String requests = "(map [r -> (list [agent-id] of item 0 r item 1 r item 2 r)] customer-requests)";
            Object demand = w.report(requests);
            cmd("set external-mode \"Disabled\" set travel-closes-shop? false set sharing-mode \"No sharing\" setup");
            if (!demand.equals(w.report(requests))) throw new AssertionError("Policy changed demand");
            cmd("set external-access-percent 25 setup");
            Object access = w.report("[agent-id] of kiosks with [external-access?]");
            cmd("set external-access-percent 75 setup");
            for (Object id : ((org.nlogo.core.LogoList)access).toJava())
                check("any? kiosks with [agent-id = \""+id+"\" and external-access?]");

            for (String mode : new String[]{"Disabled","External only","Peers then external"})
                for (int delay : new int[]{0,1,4}) {
                    cmd("initialize-controls set external-mode \""+mode+"\" set external-travel-ticks "+delay
                        + " setup repeat 100 [go] check-accounting");
                    check("requested-count = served-count + closure-failed-count + cash-failed-count + efloat-failed-count");
                }

            System.out.println("PASS: external ledger/reservations, both directions, exact delays, opening hours, "
                + "access, caps, reserve protection, peer-first fallback, closure vs staffing, demand pairing, "
                + "heterogeneity normalization and stress scenarios.");
        } finally { w.dispose(); }
        System.exit(0);
    }
}
