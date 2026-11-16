# Mobile Bank Markets

[Open the published model in NetLogo Web](https://netlogoweb.org/launch#https://raw.githubusercontent.com/gabemgem/mobile-bank-markets/main/MobileBankMarkets.nlogox)

Mobile Bank Markets is an agent-based model of liquidity sharing among mobile-money kiosk operators. It explores how trading cash and electronic balances through a network affects customers' ability to deposit and withdraw money.

Mobile-money kiosks connect cash-based local economies to electronic accounts. An operator needs cash to serve withdrawals and electronic value (e-float) to serve deposits. Even when a market has enough liquidity overall, individual kiosks can run short. Sharing liquidity with other operators may help keep these services available.

[Explore experiment results](docs/results/) · [Synthetic network generation](docs/synthetic-networks/) · [Run experiments](experiments/RUNNING.md) · [Network data guide](experiments/NETWORKS.md)

## The model

Each agent represents a kiosk operator holding cash and e-float. Customer deposits increase the operator's cash and reduce its e-float; withdrawals do the reverse. A request fails when the operator lacks the available balance needed to complete it.

Operators initiate peer trades when a balance falls below a configurable threshold. Trades exchange cash for e-float, aiming to restore a target balance while respecting reserve requirements. Committed balances are reserved until settlement, with a configurable delay of zero to two ticks.

Three sharing policies provide a comparison:

- **No sharing:** operators serve customers using their own balances.
- **Network sharing:** participating operators trade with eligible network neighbors.
- **All-to-all sharing:** participating operators can trade regardless of network ties.

The model tracks deposit and withdrawal success, requested and served transaction values, low-balance exposure, and pending and completed peer trades. These measure access to mobile-money services; the model does not simulate a complete economy of household spending.

## Networks

**Synthetic random** generates an undirected Erdos–Renyi network from the chosen kiosk count and edge density. It runs without external data files.

**Observed mutual willingness** uses surveyed kiosk operators and their reported willingness to trade. An undirected tie exists only when both operators report willingness to trade with each other. These are stated-willingness ties, rather than records of actual trades. Operators with no mutual ties remain in the network.

**Imported synthetic** loads pre-generated graphs from `synthetic-networks/`, using the same node-and-edge format as observed networks. This supports graph ensembles generated outside NetLogo, with their generation settings and seeds recorded alongside them. Synthetic libraries can be included in the repository. Real survey exports in `data/` remain excluded from Git.

**GitHub synthetic** downloads the public [920-graph library](https://github.com/gabemgem/mobile-bank-markets/tree/main/synthetic-networks) in desktop NetLogo or NetLogo Web. It includes pooled primary and corrected hub sensitivity graphs at every size from 2–24 kiosks.

See the [network data guide](experiments/NETWORKS.md) for file formats, provenance, and import instructions.

The [structural ERGM pipeline](experiments/ERGM_NETWORKS.md) fits mutual willingness-to-trade networks and generates synthetic ensembles for import, with separate fitting diagnostics and reproducible graph seeds.
The [synthetic network generation guide](docs/synthetic-networks/) explains the pooled primary generator, corrected hub sensitivity networks, repeated draws across kiosk counts, and desktop/Web loading options.

## Experiments and results

The experiment harness supports three complementary designs:

| Design | Purpose |
| --- | --- |
| One at a time (OAT) | Vary one parameter around a shared baseline while holding the others fixed. |
| Latin hypercube (LHS) | Explore joint variation across multiple parameter ranges. |
| Grid | Compare every combination of selected parameter levels. |

Repeated simulation seeds capture variation in synthetic networks and customer demand. The [results dashboard](docs/results/) displays numerical response curves, scatter plots, and heatmaps, together with parameter settings and variation across seeds. Performance benchmarks help estimate study runtime before larger experiments.

The [experiment guide](experiments/RUNNING.md) explains benchmarking, configuring studies, running and resuming batches, and exporting aggregate results. Bundled experiment configurations use synthetic random networks and require no survey data.

## Run the model

1. For desktop **NetLogo 7.0.3**, run `python scripts/install_netlogo_fetch.py` once to install the official Fetch extension, then open [MobileBankMarkets.nlogox](MobileBankMarkets.nlogox).
2. Choose **Synthetic random** to run without data, or select an imported network source and use **Choose local network**.
3. Set the controls, click **Setup**, and use **Step**, **Go / stop**, or **+100 ticks**.

Press **Setup** after changing controls to start a new run. The model's Info tab documents transaction accounting, trade timing, parameters, and assumptions. Local imports and the experiment harness use desktop NetLogo.

In NetLogo Web, use **Load GitHub library** near the bottom of the interface. Wait for **Ready: 920 GitHub graphs**, enter a graph ID such as `pooled-n20-r01` or `corrected-hub-n20-r01`, then click **Setup**. The **Use random networks** button returns to data-free simulation. The [generation guide](docs/synthetic-networks/) explains URL pinning and download handling.

## Interpretation

The model is an abstract policy experiment. Initial balances, customer demand, and trading behavior are illustrative rather than calibrated estimates of surveyed markets. Loading an observed network changes the topology; it does not make the financial behavior empirical. Network positions are illustrative, rather than geographic.

Comparisons examine when liquidity sharing improves service and how participation, topology, reserve requirements, and settlement delays limit its benefits. Demand is specified per market per tick, so comparisons across market sizes should also consider demand per kiosk.
