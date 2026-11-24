import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import org.nlogo.headless.HeadlessWorkspace;

/** Spatial ordering, frozen geography and quoted commission contracts in both swap directions. */
public class SpatialCommissionChecks {
    static HeadlessWorkspace w;
    static void cmd(String code) throws Exception { w.command(code); }
    static void check(String expression) throws Exception {
        if (!Boolean.TRUE.equals(w.report(expression))) throw new AssertionError(expression);
    }
    static void fixture() throws Exception {
        cmd("initialize-controls set number-of-kiosks 4 set network-density 0 set requests-per-tick 0 "
            + "set external-mode \"Disabled\" set commission-percent 10 setup "
            + "ask kiosk 0 [set cash 100 set efloat 900 setxy -14 -14] "
            + "ask kiosk 1 [setxy -13 -13] ask kiosk 2 [setxy -9 -14] ask kiosk 3 [setxy -9 -9] "
            + "ask kiosk 0 [create-relationships-with other kiosks] "
            + "set initial-cash sum [cash] of kiosks set initial-efloat sum [efloat] of kiosks");
    }
    static void refuse(String code) throws Exception {
        boolean refused=false;try {cmd(code);} catch(Exception expected) {refused=true;}
        if(!refused) throw new AssertionError("Should refuse: "+code);
    }
    public static void main(String[] args) throws Exception {
        byte[] digest=MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(Paths.get(args[0])));
        StringBuilder hash=new StringBuilder();for(byte b:digest)hash.append(String.format("%02x",b));
        if(!hash.toString().equals("105129cf36d2ff9fa4aeaab961b3f581586860cf30bcffe7a3474b11a1be70da"))
            throw new AssertionError("The preserved v1 file changed");
        w=HeadlessWorkspace.newInstance();
        try {
            w.open(args[1]);
            fixture();
            check("[grid-distance-to kiosk 1] of kiosk 0 = 0");
            check("[grid-distance-to kiosk 2] of kiosk 0 = 1");
            check("[grid-distance-to kiosk 3] of kiosk 0 = 2");
            cmd("ask kiosk 1 [setxy -11.5 -14]");
            check("[grid-distance-to kiosk 1] of kiosk 0 = 1");
            cmd("set grid-cell-size 33");
            check("all? kiosks [grid-distance-to kiosk 0 = 0]");

            fixture();
            cmd("ask kiosk 0 [book-transfer kiosk 1 100 true] check-accounting");
            check("settled-count = 1 and count transfers = 0 and closed-kiosk-ticks = 0");
            check("[cash] of kiosk 0 = 190 and [efloat] of kiosk 0 = 800");
            check("[cash] of kiosk 1 = 410 and [efloat] of kiosk 1 = 600");
            check("commissions-earned = 10 and commissions-paid = 10 and subsidy-spent = 0");
            fixture();
            cmd("ask kiosk 1 [set cash 900 set efloat 100] "
                + "set initial-cash sum [cash] of kiosks set initial-efloat sum [efloat] of kiosks "
                + "ask kiosk 0 [rebalance] check-accounting");
            check("abs ([cash] of kiosk 0 - 500) < 0.000001");
            check("abs (settled-value - 400 / 0.9) < 0.000001");

            fixture();
            cmd("ask kiosk 0 [set cash 900 set efloat 100] "
                + "ask kiosk 1 [set cash 100 set efloat 900] "
                + "set initial-cash sum [cash] of kiosks set initial-efloat sum [efloat] of kiosks "
                + "ask kiosk 0 [rebalance] check-accounting");
            check("[cash] of kiosk 0 = 460 and [efloat] of kiosk 0 = 500");
            check("commissions-paid = 40 and [cash] of kiosk 1 = 540");

            fixture();
            cmd("ask kiosk 0 [set cash 150 set efloat 0] "
                + "set initial-cash sum [cash] of kiosks set initial-efloat sum [efloat] of kiosks "
                + "ask kiosk 0 [rebalance] check-accounting");
            check("abs ([cash] of kiosk 0 - minimum-reserve) < 0.000001");
            check("abs (settled-value - 50 / 1.1) < 0.000001");

            // Distance precedes price, with feasibility checked before either ranking.
            fixture();
            cmd("ask kiosk 1 [set cash 100 set efloat 900] "
                + "ask kiosk 2 [set commission-rate 0.05] ask kiosk 3 [set commission-rate 0] "
                + "set initial-cash sum [cash] of kiosks set initial-efloat sum [efloat] of kiosks "
                + "ask kiosk 0 [rebalance] check-accounting");
            check("[partner] of [pending-transfer] of kiosk 0 = kiosk 2");
            fixture();
            cmd("ask kiosk 1 [setxy -9 -13 set commission-rate 0.05] "
                + "ask kiosk 2 [set commission-rate 0.01] ask kiosk 3 [set commission-rate 0] "
                + "ask kiosk 0 [rebalance] check-accounting");
            check("[partner] of [pending-transfer] of kiosk 0 = kiosk 2");
            fixture();
            cmd("ask kiosk 1 [set commission-rate 0.5] ask kiosk 2 [set commission-rate 0] "
                + "ask kiosk 0 [rebalance] check-accounting");
            check("[earned-commissions] of kiosk 1 > 0 and [earned-commissions] of kiosk 2 = 0");
            fixture();
            cmd("ask kiosk 0 [ask relationship-with kiosk 1 [die]] ask kiosk 0 [rebalance]");
            check("[partner] of [pending-transfer] of kiosk 0 = kiosk 2");

            Set<Object> chosen=new HashSet<>();
            for(int seed=1;seed<=20;seed++) {
                fixture();
                cmd("ask kiosk 1 [setxy -9 -13] ask kiosk 0 [ask relationship-with kiosk 3 [die]] "
                    + "random-seed "+seed+" ask kiosk 0 [rebalance]");
                chosen.add(w.report("[who] of [partner] of [pending-transfer] of kiosk 0"));
            }
            if(chosen.size()!=2)throw new AssertionError("Equal-distance/rate ties were not randomized");

            fixture();
            cmd("set commission-subsidy-percent 50 ask kiosk 0 [book-transfer kiosk 3 100 true] "
                + "ask kiosks [set participating? false] check-accounting");
            check("subsidy-spent = 0 and sum [subsidized-fee] of transfers = 5");
            check("sum [reserved-efloat] of kiosks = 100 and sum [reserved-cash] of kiosks = 100");
            cmd("set commission-subsidy-percent 100 ask kiosks [set commission-rate 0.5] "
                + "go go");
            check("settled-count = 0 and closed-kiosk-ticks = 2");
            cmd("go check-accounting");
            check("settled-count = 1 and commissions-earned = 10 and commissions-paid = 5 and subsidy-spent = 5");
            check("sum [cash] of kiosks = initial-cash + 5 and sum [efloat] of kiosks = initial-efloat");

            fixture();
            cmd("set commission-subsidy-percent 100 ask kiosk 0 [book-transfer kiosk 1 100 true] check-accounting");
            check("[cash + efloat] of kiosk 0 = 1000 and commissions-paid = 0 and subsidy-spent = 10");
            fixture();
            cmd("set travel-closes-shop? false ask kiosk 0 [set cash 900 set efloat 100] "
                + "set initial-cash sum [cash] of kiosks set initial-efloat sum [efloat] of kiosks "
                + "ask kiosk 0 [book-transfer kiosk 3 100 false] check-accounting");
            check("[reserved-cash] of kiosk 0 = 110 and [reserved-efloat] of kiosk 3 = 100");
            cmd("ask kiosk 0 [serve-request 800 true] check-accounting");
            check("cash-failed-count = 1 and closure-failed-count = 0");

            cmd("initialize-controls set commission-mode \"Varied\" setup");
            check("all? kiosks [commission-rate >= 0.005 and commission-rate <= 0.015]");
            Object rates=w.report("map [a -> [commission-rate] of a] sort kiosks");
            Object positions=w.report("map [a -> (list [xcor] of a [ycor] of a)] sort kiosks");
            cmd("set commission-subsidy-percent 100 set grid-cell-size 2 setup");
            if(!rates.equals(w.report("map [a -> [commission-rate] of a] sort kiosks")))
                throw new AssertionError("Subsidy or grid size redrew commission rates");
            if(!positions.equals(w.report("map [a -> (list [xcor] of a [ycor] of a)] sort kiosks")))
                throw new AssertionError("Policy changed the spring geography");
            cmd("repeat 5 [go]");
            if(!positions.equals(w.report("map [a -> (list [xcor] of a [ycor] of a)] sort kiosks")))
                throw new AssertionError("Trading moved kiosks");

            for(String mode:new String[]{"Uniform","Varied"})
                for(int subsidy:new int[]{0,50,100})
                    for(int cell:new int[]{1,5,33}) {
                        cmd("initialize-controls set commission-mode \""+mode+"\" set commission-subsidy-percent "+subsidy
                            +" set grid-cell-size "+cell+" setup repeat 60 [go] check-accounting");
                    }
            refuse("set commission-percent 100 validate-controls");
            cmd("initialize-controls");refuse("set commission-min-percent 2 set commission-max-percent 1 validate-controls");
            cmd("initialize-controls");refuse("set grid-cell-size 0 validate-controls");
            System.out.println("PASS: v1 hash, Manhattan cells/boundaries, instant and delayed trades, feasible-nearest/cheapest/random ties, "
                +"cash and e-float quotes, fee reservations, frozen quotes, partial/full subsidy, reproducible/frozen layout and rates, "
                +"18 accounting stress scenarios and validation.");
        } finally {w.dispose();}
        System.exit(0);
    }
}
