# Generating the ABM network library

The primary generator is the pooled degree-plus-closure ERGM selected by
[nested internal validation](NESTED_NETWORK_VALIDATION.md). Corrected hub graphs
are a structural sensitivity alternative. Both generate undirected mutual
stated willingness-to-trade networks, including isolates; no actor homophily
or actual transaction ties are fitted.

The [configuration](configs/generate_abm_networks.R) specifies sizes 2–24, 20
graphs per size and family, and four matched whole-market bootstrap refits. A
separate all-market point fit is retained as a reference. Exported graphs use
the four bootstrap parameter tuples equally: five graphs per tuple at each size.
Every graph uses an independent seed. The pooled size-dependent edge coefficient
is `beta0 + beta_size * log(n)`. Corrected hub graphs first draw a count from the
corrected logistic-normal/binomial law, then arrange ties conditionally on that
count with generated activity and a closure-mixture draw.

Repeated adjacency shapes are retained, including empty and complete graphs.
For two nodes there are only two possible simple undirected graphs, so independent
replicates cannot be forced to have distinct shapes without changing the model.

## Refit and generate

From `ABM/`, with private observed network exports in `data/`:

```powershell
Rscript tests/abm_network_generation_checks.R
Rscript scripts/generate_abm_networks.R --phase prepare
Rscript scripts/generate_abm_networks.R
python scripts/document_synthetic_library.py
```

The sequential command fits the full-data pair, then four matched bootstrap
pairs, then generates the CSV library. It refuses to replace a nonempty output
directory. Successful output is checksummed; rerunning verifies the existing
library rather than overwriting it. Changing code, data, configuration, or the
output option requires a fresh `--work` folder. Failed stages are retained and
stop the run; no bootstrap fit is silently dropped.

For independent parallel fits, prepare once, then run these in separate terminals
with the same work directory:

```powershell
Rscript scripts/generate_abm_networks.R --phase fit --fit point
Rscript scripts/generate_abm_networks.R --phase fit --fit 1
Rscript scripts/generate_abm_networks.R --phase fit --fit 2
Rscript scripts/generate_abm_networks.R --phase fit --fit 3
Rscript scripts/generate_abm_networks.R --phase fit --fit 4
# After all five finish:
Rscript scripts/generate_abm_networks.R --phase generate
python scripts/document_synthetic_library.py
```

Never edit active runner/helper files. Each fit writes a separate checkpoint
directory. `--input`, `--config`, `--work`, and `--out` allow separate studies;
use the same options for preparation, fitting, and generation. Default estimation
artifacts are under ignored `local-abm-network-generation/`. This includes fit
objects, source-market memberships, coefficients, density/activity/closure
calibrations, warnings, source/data hashes, and generation checksums.

## Library contents

The default versionable output is `synthetic-networks/`:

- `networks.csv`: 920 graph records, generator and primary/sensitivity role,
  replicate, graph seed, bootstrap fit ID, and realized graph statistics.
- `nodes.csv`: all generated nodes, including isolates.
- `edges.csv`: one copy of each undirected edge.

The documentation helper adds `README.md` and `manifest.json` with canonical-LF
SHA-256 checksums, source/config checksums, size/replicate counts, and anonymous fit
labels. It reads only generated files and public source, not private fit objects.
For an alternate output folder, pass `--library path` to that helper too.

Graph IDs follow `pooled-n12-r03` or `corrected-hub-n12-r03`. Node IDs are fresh
anonymous labels scoped to each graph. No respondent IDs, source-market IDs,
observed adjacencies, or fitted objects are exported into this library. These
are fitted synthetic draws, not a formal differential-privacy mechanism.
Review generated files separately from private estimation artifacts before a
public release. This command does not commit, push, or publish anything.

Use the three files together; moving one without the others breaks the import.
The graph seed is distinct from the NetLogo simulation seed. To regenerate
exact draws, retain the private fitted parameter tuples as well as code/config
and graph seeds.

## NetLogo checks

Desktop NetLogo 7.0.3 reads the library through **Imported synthetic**. The chooser
offers generator, size, then graph ID. The importer caches the CSVs between runs;
reopen the chooser or call `reload-network-library` after replacing a library.
The three sharing policies use the same supplied graph/node population.

`tests/SyntheticLibraryChecks.java` checks every adjacency, node/tie/isolate and
maximum-degree count, and accounting for all 920 graphs. It exercises all three
policies at sizes 2, 13, and 24 for both families. Compile with the NetLogo jars:

```powershell
javac -cp "C:/Program Files/NetLogo 7.0.3/app/*" -d local-abm-network-generation/checks/classes tests/SyntheticLibraryChecks.java
java "-Dnetlogo.extensions.dir=C:/Program Files/NetLogo 7.0.3/extensions" -cp "local-abm-network-generation/checks/classes;C:/Program Files/NetLogo 7.0.3/app/*" SyntheticLibraryChecks "ABSOLUTE_PATH_TO/MobileBankMarkets.nlogox"
```

`tests/PortableChecks.java` separately verifies abstract-mode startup without
data, explicit missing-library errors, importer isolates, and operation without
parameter widgets. No NetLogo test loads the private observed network source.

## Website and Web model

The explanatory page is `docs/synthetic-networks/index.md`. The README and Pages
landing page link to it without changing the project landing path. The page is
descriptive; it does not contain fit objects or copies of the generated library.

The current NetLogo importer remains desktop-only. A NetLogo Web loader needs
asynchronous Fetch plus `csv:from-string`, or bundled NetLogo 7 resources. Merely
pushing companion CSVs does not make desktop file operations work in a browser.
Root library files would need raw GitHub URLs, or deliberate placement under the
Pages source. The official documentation and checked hosting behavior are linked
on the site page. No live browser import of these unpublished CSVs is claimed.
