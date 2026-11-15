# Running synthetic experiments

Run commands in PowerShell from the `ABM` directory. Python 3.10+, a JDK
(`java` and `javac`), and NetLogo 7.0.3 are required. No survey files are needed.
If Java is not on PATH, append `--java 'C:/path/to/java.exe' --javac 'C:/path/to/javac.exe'`.
If NetLogo is elsewhere, append `--netlogo-home 'C:/path/to/NetLogo 7.0.3'`.

## 1. Measure this computer before a full study

```powershell
python experiments/performance.py --out results/performance-new
```

The default benchmark has **24 measured runs plus two discarded warm-ups**: six
workloads, two horizons (50 and 500 ticks), and two seeds. It covers sparse/dense
graphs, different sizes and demand levels, and all sharing policies. It is a
performance test, not an experiment establishing policy effects. Detailed setup,
simulation, and metric-extraction timings are in the output. `profile.json`
contains runtime estimates for the prepared studies. Use a new output directory
for a fresh benchmark; `--resume` resumes an identical interrupted one.

A 500-tick benchmark was run during setup under `results/performance-500/`.
Use a fresh benchmark after changing the model/runner, switching computers, or
changing workload substantially. The dashboard shows the last exported benchmark;
it is not a universal performance guarantee. The harness is serial; logical CPU
count does not imply parallel execution.

Use `--ticks 20 80 --repeats 1` for a faster initial check. Short-horizon profiles
extrapolate when estimating 500-tick studies. More repeats improve timing stability.
Warm-ups are not written as experiment responses, but their time is included in
the planning estimate. Compilation/JVM/model-loading overhead is measured too.

## 2. Inspect counts and estimated runtime without launching the study

```powershell
python experiments/run_experiments.py experiments/configs/oat.json --out results/oat --profile results/performance-500/profile.json --dry-run --resume
python experiments/run_experiments.py experiments/configs/lhs.json --out results/lhs --profile results/performance-500/profile.json --dry-run --resume
python experiments/run_experiments.py experiments/configs/grid.json --out results/grid --profile results/performance-500/profile.json --dry-run --resume
```

Replace the profile path if you just made a fresh benchmark. Dry runs write the
design and manifest but execute **zero NetLogo runs**. Inspect `design.csv` before
starting. Estimates match the current model and Java runner hashes; changed
versions are rejected. Estimates combine measured setup time and tick rates from
the nearest policy/workload case. A planning allowance uses at least 1.5 times
run costs and the slowest measured tick rate. It is **not a confidence interval**.
Unmeasured workloads/horizons are flagged. Background load, late-run matching
activity, memory pressure, and JIT behavior can change actual elapsed time.

## 3. Run one chosen study

Because step 2 already created the output folders, use `--resume`:

```powershell
python experiments/run_experiments.py experiments/configs/oat.json --out results/oat --profile results/performance-500/profile.json --resume
python experiments/run_experiments.py experiments/configs/lhs.json --out results/lhs --profile results/performance-500/profile.json --resume
python experiments/run_experiments.py experiments/configs/grid.json --out results/grid --profile results/performance-500/profile.json --resume
```

Run these individually, not simultaneously, if you want the benchmark estimate
to remain applicable. Progress is written to each `run.log`. Ctrl+C retains
completed checkpoints; rerun the same command to resume. Do not change a study's
config/model after starting it; use a new output folder for a revised experiment.

| Study | Settings | Seeds per setting | Measured runs | Ticks/run | Main question |
| --- | ---: | ---: | ---: | ---: | --- |
| OAT | 15 | 10 | 150 | 500 | Which single changes matter near the baseline? |
| LHS | 80 | 10 | 800 | 500 | How do responses vary when nine inputs change jointly? |
| Grid | 54 | 10 | 540 | 500 | How do policy, density, delay, and participation interact? |

Each batch adds two warm-up runs, excluded from those measured counts. Repeated
seeds account for both synthetic graph and demand randomness. A simulation seed
is a replicate, not a confidence guarantee. The same seed list is used at every
setting. OAT baseline differences pair by seed; joint designs average responses
at each parameter setting before computing marginal rank correlations.

OAT varies density, participation, delay, low-balance trigger, refill target,
reserve, and demand. LHS also varies network size and demand polarization.
Targets stay above triggers, so LHS does not need constraint-based point dropping.
Grid fixes size and demand while crossing three policies, three densities, three
delays, and two participation levels. Some no-sharing cells are deliberately
redundant controls: their service should not depend on peer-trade parameters.
LHS size/demand changes alter demand per kiosk; marginal correlations do not
isolate causal effects. These are uncalibrated Erdos-Renyi graph experiments.

## 4. Review outputs, then stage a public synthetic report

Inspect `results.csv`, `summary.csv`, and `oat_effects.csv` or
`rank_sensitivity.csv`. Verify all expected seeds succeeded. Inspect requested
values before interpreting zero service rates, since no-demand rates use a zero
placeholder. Error bars on the dashboard show between-seed SD, not standard
errors or confidence intervals. OAT response curves use the actual numeric
parameter values on the horizontal axis, including unequal spacing. The default
view shows mean responses and between-seed SD; the paired-change view shows
paired differences and their SD. Baseline is marked explicitly. Lines connect
tested settings and do not predict intermediate responses. The settings table
shows the complete study baseline and highlights the single parameter varied
in the current OAT curve; all others are held at those baseline values.

```powershell
python experiments/export_report.py results/oat --id oat --title "OAT sensitivity · 10 seeds"
python experiments/export_report.py results/lhs --id lhs --title "Joint sensitivity · 10 seeds"
python experiments/export_report.py results/grid --id grid --title "Policy grid · 10 seeds"
```

The exporter stages sanitized aggregate JSON in `docs/results/studies/`. It
requires complete successful abstract Synthetic random runs. It refuses observed
or imported synthetic libraries, private network IDs, and manifests referencing
local network data. Raw runs, logs, private datasets, and machine paths are not
copied. Review staged files before committing. Use `--replace` only when you
intend to replace an existing staged report. This command does not commit, push,
or deploy anything.

To update the dashboard's small performance report after benchmarking:

```powershell
python experiments/performance.py --out results/performance-new --public-report docs/results/studies/performance.json
```

Use this flag during the original benchmark invocation, or `--resume` for the
same completed benchmark to export without rerunning successful cases.

## 5. Preview and preserve the project landing page

```powershell
python experiments/sync_project_page.py
python -m http.server 8000 --directory docs
```

Open `http://localhost:8000/results/` to preview the dashboard. The simple local
server previews static dashboard files; GitHub Pages renders the Markdown landing
page. The **README remains the project overview source**. The sync script creates
`docs/index.md` from it; dashboard files live under `docs/results/`. Relative links
preserve `<your custom URL>/mobile-bank-markets` as the landing path and put the
dashboard at `/mobile-bank-markets/results/`. No CNAME or custom-domain setting
is changed by these scripts.

For standard GitHub Pages branch hosting, keep the existing custom domain and
choose `main` / `/docs` as the publishing source in repository Settings → Pages.
If the custom host already renders the README through another mechanism, retain
that mechanism and serve `docs/results/` under its existing project route instead.
See [GitHub's publishing-source documentation](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).
Only the intended source code, configs, documentation, and reviewed synthetic
summaries and synthetic network libraries can be committed. `data/`, raw
`results/`, and `local-.../` directories remain ignored. See the
[network data guide](NETWORKS.md) for library formats and provenance. Large experiments and publication are separate deliberate steps.
