import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import org.nlogo.core.LogoList;
import org.nlogo.headless.HeadlessWorkspace;

/** Executes the validated, explicit design written by run_experiments.py. */
public class BatchRunner {
    static final String[] NAMES = {
        "n_kiosks", "n_links", "network_type", "active_market", "service_pct",
        "deposit_service_pct", "withdrawal_service_pct", "requested_count", "served_count",
        "deposit_requested_value", "withdrawal_requested_value", "deposit_served_value",
        "withdrawal_served_value", "trades_started", "trades_settled", "pending_trades",
        "settled_value", "pending_value", "reserved_cash", "reserved_efloat",
        "trade_attempts", "unmet_attempts", "cash_low_share", "efloat_low_share", "final_cash", "final_efloat"
    };
    static final String[] REPORTERS = {
        "count kiosks", "count relationships", "network-description", "active-market", "percent-served -1",
        "percent-served 0", "percent-served 1", "requested-count", "served-count",
        "item 0 requested-values", "item 1 requested-values", "item 0 served-values",
        "item 1 served-values", "initiated-count", "settled-count", "count transfers",
        "settled-value", "sum [quantity] of transfers", "sum [reserved-cash] of kiosks",
        "sum [reserved-efloat] of kiosks", "trade-attempts", "unmet-attempts",
        "cash-low-ticks / (count kiosks * ticks)", "efloat-low-ticks / (count kiosks * ticks)",
        "sum [cash] of kiosks", "sum [efloat] of kiosks"
    };
    static final String[] V2_NAMES = {
        "external_started", "external_settled", "external_value", "external_pending",
        "external_pending_value", "net_external_cash", "closed_share", "closure_failed_count",
        "closure_failed_value", "cash_failed_count", "efloat_failed_count", "commissions_earned",
        "commissions_paid", "subsidy_spent", "pending_commissions", "pending_subsidy", "mean_peer_distance"
    };
    static final String[] V2_REPORTERS = {
        "external-started", "external-settled", "external-value", "count transfers with [external?]",
        "sum [quantity] of transfers with [external?]", "net-external-cash",
        "closed-kiosk-ticks / (count kiosks * ticks)", "closure-failed-count", "closure-failed-value",
        "cash-failed-count", "efloat-failed-count", "commissions-earned", "commissions-paid",
        "subsidy-spent", "sum [commission-fee] of transfers", "sum [subsidized-fee] of transfers",
        "ifelse-value (initiated-count > 0) [peer-distance-total / initiated-count] [0]"
    };
    static String[] concat(String[] a, String[] b) {
        String[] result = Arrays.copyOf(a, a.length+b.length);
        System.arraycopy(b, 0, result, a.length, b.length);
        return result;
    }
    static String csv(Object value) {
        return "\"" + String.valueOf(value).replace("\r", " ").replace("\n", " ")
            .replace("\"", "\"\"") + "\"";
    }
    public static void main(String[] args) throws Exception {
        if (args.length != 5) throw new IllegalArgumentException("model, work.tsv, attempts.csv, timing.json, warmup count required");
        Path results = Paths.get(args[2]);
        boolean header = !Files.exists(results) || Files.size(results) == 0;
        HeadlessWorkspace model = HeadlessWorkspace.newInstance();
        int failed = 0;
        long engineStart = System.nanoTime();
        double warmupSeconds = 0;
        try (BufferedWriter out = Files.newBufferedWriter(results, StandardCharsets.UTF_8,
                StandardOpenOption.CREATE, StandardOpenOption.APPEND)) {
            model.open(args[0]);
            model.command("initialize-controls");
            boolean v2;
            try { v2 = "v2".equals(model.report("model-version")); }
            catch (org.nlogo.core.CompilerException ex) { v2 = false; }
            String[] names = v2 ? concat(NAMES, V2_NAMES) : NAMES;
            String[] reporters = REPORTERS.clone();
            if (v2) {
                // Existing peer metrics retain their meaning when external transfers are present.
                reporters[15] = "count transfers with [not external?]";
                reporters[17] = "sum [quantity] of transfers with [not external?]";
                reporters = concat(reporters, V2_REPORTERS);
            }
            if (header) {
                out.write("run_id,status,error,seconds,setup_seconds,simulation_seconds,metrics_seconds," + String.join(",", names));
                out.newLine(); out.flush();
            }
            List<String> lines = Files.readAllLines(Paths.get(args[1]), StandardCharsets.UTF_8);
            String metrics = "(list " + String.join(" ", Arrays.stream(reporters)
                .map(s -> "(" + s + ")").toArray(String[]::new)) + ")";
            if (!lines.isEmpty()) {
                String[] first = lines.get(0).split("\t", -1);
                String firstCommands = new String(Base64.getDecoder().decode(first[2]), StandardCharsets.UTF_8);
                long warmupStart = System.nanoTime();
                for (int i=0; i<Integer.parseInt(args[4]); i++) {
                    model.command(firstCommands);
                    model.command("setup repeat " + first[1] + " [go] check-accounting");
                }
                warmupSeconds = (System.nanoTime()-warmupStart)/1e9;
            }
            for (int index = 0; index < lines.size(); index++) {
                String[] fields = lines.get(index).split("\t", -1);
                String runId = fields[0];
                int steps = Integer.parseInt(fields[1]);
                String commands = new String(Base64.getDecoder().decode(fields[2]), StandardCharsets.UTF_8);
                long start = System.nanoTime();
                String status = "ok", error = "";
                double setupSeconds = 0, simulationSeconds = 0, metricsSeconds = 0;
                List<Object> values = new ArrayList<>(Collections.nCopies(names.length, ""));
                try {
                    long phase = System.nanoTime();
                    model.command(commands + " setup");
                    setupSeconds = (System.nanoTime()-phase)/1e9;
                    phase = System.nanoTime();
                    model.command("repeat " + steps + " [go] check-accounting");
                    simulationSeconds = (System.nanoTime()-phase)/1e9;
                    phase = System.nanoTime();
                    values = ((LogoList) model.report(metrics)).toJava();
                    metricsSeconds = (System.nanoTime()-phase)/1e9;
                } catch (Exception ex) {
                    status = "error"; error = ex.toString(); failed++;
                }
                List<Object> row = new ArrayList<>();
                row.add(runId); row.add(status); row.add(error);
                row.add((System.nanoTime() - start) / 1e9); row.addAll(values);
                row.add(4, setupSeconds); row.add(5, simulationSeconds); row.add(6, metricsSeconds);
                out.write(String.join(",", row.stream().map(BatchRunner::csv).toArray(String[]::new)));
                out.newLine(); out.flush();
                if ((index + 1) % 10 == 0 || index + 1 == lines.size()) {
                    System.out.println("Finished " + (index + 1) + "/" + lines.size() + "; errors=" + failed);
                }
            }
        } finally { model.dispose(); }
        String timing = "{\"engine_seconds\":" + ((System.nanoTime()-engineStart)/1e9)
            + ",\"warmup_seconds\":" + warmupSeconds + ",\"warmup_runs\":" + args[4] + "}";
        Files.write(Paths.get(args[3]), timing.getBytes(StandardCharsets.UTF_8));
        System.exit(failed == 0 ? 0 : 1);
    }
}
