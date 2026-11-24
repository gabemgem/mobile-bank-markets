# Network data and imports

The model supports built-in random networks and two optional CSV libraries. Select
**Synthetic random** to run without any files. For an imported library, choose its
network source, click **Choose local network**, select an ID, and click **Setup**.
Kiosk count and density controls apply only to built-in random networks.

## Library format

Store observed networks in `data/` and generated networks in `synthetic-networks/`,
relative to the ABM directory. Both use the same format:

| File | Required leading columns | Contents |
| --- | --- | --- |
| `networks.csv` | `network_id,network_type` | One row per graph |
| `nodes.csv` | `network_id,node_id` | Every node, including isolates |
| `edges.csv` | `network_id,source,target` | Each undirected edge once |

Use nonnumeric string IDs, such as `synthetic-001` and `node-a`. IDs must agree
across files; both endpoints must appear in nodes.csv. The importer rejects
duplicate nodes, missing endpoints, self-links, and duplicate undirected edges.
Missing library files produce an error; select Synthetic random for a data-free run.

Additional catalog columns can record node/link/isolate counts, the generator,
graph-generation seed, target statistics, and fit diagnostics. Use a descriptive
synthetic type such as `synthetic-degree-matched`. NetLogo reads the leading fields
and adjacency; graph fitting and diagnostics take place outside the simulation.
Graph-generation seeds and simulation seeds serve different purposes and should
be recorded separately.

The supplied library has 20 graphs for each size 2–24 from each of two generators:
pooled degree-plus-closure (primary) and corrected hub (sensitivity), 920 graphs in
total. Both use four equally weighted market-bootstrap fits. See
[generation commands](GENERATE_ABM_NETWORKS.md) and the
[site explanation](../docs/synthetic-networks/).

The chooser filters catalogs with `generator` and `n_nodes` metadata before
offering graph IDs. CSV tables are cached across imported Setup calls. Reopen
**Choose local network** or run `reload-network-library` after changing files.
Switching to Synthetic random clears the cache; the data-free mode remains
independent of both libraries.

`synthetic-networks/` is available for versioned graph libraries. Private exploratory
files can instead live under an ignored `local-.../` directory. The built-in imported
synthetic mode reads `synthetic-networks/`; it does not read those alternate folders.
`data/`, raw `results/`, and `local-.../` directories remain Git-ignored.

## Observed network provenance

The export source is
`../data/Agent Survey Data/02 Datasets/agents_social_network_survey_data.xls`, Sheet1.
All files under `data/` are real survey-derived exports. They include the common
library files and `market_nodes.csv`, `mutual_edges.csv`, `markets.csv`, and
`import_audit.csv`. The audit records the source checksum and cleaning counts.

An undirected edge requires Yes reports in both directions. The exporter normalizes
IDs, removes self/cross-market reports, collapses duplicate directed reports using
any Yes, and excludes nominated nonrespondents. Missing reverse reports create no
edge and are not interpreted as explicit refusals. Respondents without mutual ties
remain as isolates. The source relationship list cannot recover omitted roster
members; the additional attitude survey does not supply invented edges.

With R and the `readxl` package installed, regenerate exports from the ABM directory:

```powershell
Rscript ./scripts/export_market_networks.R
```

The optional argument is the project root containing `ABM/` and
`data/Agent Survey Data/`. Rebuild exports after changing the source workbook.
Network selection reads the catalog at runtime, so no model-file update is needed.

## Experiment configuration

For structural ERGMs fitted to the mutual willingness networks, see the
[ERGM generation pipeline](ERGM_NETWORKS.md). It fits candidate models, produces
diagnostics, and exports graph ensembles in this library format.

Set `network-source` to `Imported synthetic` or `Observed mutual willingness` and
`selected-market` to a catalog network ID. The legacy name `selected-market` applies
to either library. It can also be swept over several IDs. A blank ID selects the
first catalog entry. Source IDs and types appear in local run outputs.

Demand and wealth remain synthetic in imported modes. Network sharing uses the
loaded edges, all-to-all sharing bypasses them while retaining the nodes, and no
sharing suppresses peer swaps.

For summary-matched synthetic ensembles, candidate targets include size, density,
degree distribution, isolates, component sizes, and clustering. Check realized
statistics for every generated graph and retain generator settings and diagnostics.
The NetLogo model imports such libraries; it does not fit them. The public report
exporter accepts only built-in Synthetic random studies; imported-library studies
remain available through the local harness outputs.

## NetLogo Web

Both `MobileBankMarkets_v1.nlogox` (abstract) and `MobileBankMarkets_v2.nlogox`
(policy model) support the same local and GitHub libraries. The
[version guide](VERSIONS.md) documents v2's additional mechanisms and parameters.

Select **GitHub synthetic**, or click **Load GitHub library**, in the shared model.
The URL input defaults to the public root-level `synthetic-networks/` directory
on raw.githubusercontent.com. Wait for **Ready: 920 GitHub graphs**, select an ID
from the v2 dropdown (or type it in v1), and click **Setup**. For example,
`pooled-n20-r01` is pooled generator, 20 kiosks, replicate 1. The source chooser
and URL/ID controls work in both Web and desktop NetLogo; **Choose
local network** remains a desktop-only path for the local import modes.

All three CSVs must pass validation before any remote graph is available. Cancel
or timeout discards partial results, and stale replies are ignored. Web HTTP
failures may display a standard Web error dialog; missing replies expire after
30 seconds when the status monitor, Setup, or Go checks. Use **Load GitHub
library** to retry or **Use random networks** for data-free operation.

Pin a reproducible base URL by replacing `main` with a commit SHA. Use a raw
directory URL without a filename or trailing slash; GitHub `blob` pages are HTML.
The Pages site built from `docs/` does not automatically serve the root library.
See the [generation page](../docs/synthetic-networks/) for direct download links.

Desktop prerequisite (including headless experiments): run
`python scripts/install_netlogo_fetch.py` once. It verifies and installs the
official Fetch 1.0.5 extension, compatible with the Java 11 harness. Web supplies
Fetch itself. Random networks and local imports never make HTTP requests.
