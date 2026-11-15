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
