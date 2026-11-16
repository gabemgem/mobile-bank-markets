# Synthetic market networks

This library contains 920 newly generated undirected mutual stated
willingness-to-trade graphs: 20 replicates per generator
at every kiosk count from 2 to 24.

- **pooled**: primary pooled degree-plus-closure ERGM.
- **corrected_hub**: latent-activity, corrected-density/closure sensitivity alternative.

Each generator uses 4 equally weighted whole-market bootstrap refits.
The all-market point fit is a separate reference, not an extra ensemble member.
Graph seeds and parameter-fit labels are recorded in networks.csv. Financial
behavior and simulation seeds remain separate NetLogo settings.

Keep networks.csv, nodes.csv, and edges.csv together. All nodes, including
isolates, are supplied; each undirected edge appears once. Repeated graph shapes,
empty graphs, and complete graphs are retained as valid random outcomes.

In desktop NetLogo 7.0.3, open ../MobileBankMarkets.nlogox, choose **Imported
synthetic**, then use **Choose local network** to select generator, size, and ID.
Reopen the chooser after replacing files to refresh the in-memory cache.
In NetLogo Web, click **Load GitHub library**, wait for **Ready: 920 GitHub
graphs**, enter an ID such as `pooled-n20-r01` or `corrected-hub-n20-r01`,
and click **Setup**. The default URL downloads this published library directly.
For desktop/headless use, first run `python scripts/install_netlogo_fetch.py`
from the repository directory to install the official Fetch extension.

All node and graph IDs are synthetic. No respondent IDs, observed adjacencies,
or fit objects are included. Generation from fitted survey structure is not a
formal privacy guarantee; review this library before public release. Private
fits and source-market resamples stay under ignored local directories.

The manifest records canonical-LF checksums so verification survives Git line-ending
conversion. Reproducing a graph also requires its private fitted parameter tuple.
See [generation instructions](../experiments/GENERATE_ABM_NETWORKS.md) and the
[site explanation](../docs/synthetic-networks/index.md).
