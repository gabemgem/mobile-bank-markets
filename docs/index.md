---
layout: default
title: Mobile Bank Markets
---

<!-- Generated from README.md by experiments/sync_project_page.py -->

# Mobile Bank Markets

[Open v2 in NetLogo Web](https://netlogoweb.org/launch#https://raw.githubusercontent.com/gabemgem/mobile-bank-markets/main/MobileBankMarkets_v2.nlogox) · [Open v1 in NetLogo Web](https://netlogoweb.org/launch#https://raw.githubusercontent.com/gabemgem/mobile-bank-markets/main/MobileBankMarkets_v1.nlogox)

Mobile Bank Markets is an agent-based model of liquidity sharing among mobile-money kiosk operators. It explores how trading cash and electronic balances through a network affects customers' ability to deposit and withdraw money.

Mobile-money kiosks connect cash-based local economies to electronic accounts. An operator needs cash to serve withdrawals and electronic value (e-float) to serve deposits. Even when a market has enough liquidity overall, individual kiosks can run short. Sharing liquidity with other operators may help keep these services available.

[Explore experiment results](results/) · [Synthetic network generation](synthetic-networks/) · [Run experiments](https://github.com/gabemgem/mobile-bank-markets/blob/main/experiments/RUNNING.md) · [Network data guide](https://github.com/gabemgem/mobile-bank-markets/blob/main/experiments/NETWORKS.md)

## Model versions

| Version | What it contains |
| --- | --- |
| [V1 — abstract model](https://github.com/gabemgem/mobile-bank-markets/blob/main/MobileBankMarkets_v1.nlogox) | Preserved peer-sharing model: equal initial balances, uniform customer traffic, alternating deposit/withdrawal tendencies, reserved balances, and a 0–2 tick settlement delay. No external rebalancing or shop closure. |
| [V2 — policy model](https://github.com/gabemgem/mobile-bank-markets/blob/main/MobileBankMarkets_v2.nlogox) | Adds external rebalancing, unequal demand, spring-layout grid travel, and optional shop closure. Agents choose feasible partners by distance, then commission. Uniform or varied supplier fees and external fee subsidies track who pays. |

V1 is the simple sandbox for exploring network liquidity sharing. V2 extends that
foundation for policy comparisons, with explicit geography and commission assumptions. Both accept the same synthetic libraries and retain data-free random
networks. Neither version predicts exact effects in surveyed markets. The
[version and assumptions guide](https://github.com/gabemgem/mobile-bank-markets/blob/main/experiments/VERSIONS.md) explains the controls
and experiment settings.

## The model

Each agent represents a kiosk operator holding cash and e-float. Customer deposits increase the operator's cash and reduce its e-float; withdrawals do the reverse. A request fails when the operator lacks the available balance needed to complete it.

Operators initiate peer trades when a balance falls below a configurable threshold. Trades exchange cash for e-float, aiming to restore a target balance while respecting reserve requirements. Committed balances are reserved until settlement, after a configurable 0–2 tick delay in v1. In v2, peer travel follows Manhattan grid distance on a fixed spring layout: same-square trades settle immediately, and each horizontal or vertical square adds one tick.

Both versions retain three peer-sharing policies:

- **No sharing:** peer exchanges are disabled.
- **Network sharing:** participating operators trade with eligible network neighbors.
- **All-to-all sharing:** participating operators can trade regardless of network ties.

V2 can disable external rebalancing, use it alone, or try peers before falling back to it. External exchanges change the cash/e-float mix without adding working capital. Travel can interrupt service; a staffing switch lets the shop remain open. Customer requests lost during closure remain part of demand. Peer suppliers charge a cash commission, drawn once per agent from a uniform range or set equally for all. V2 prioritizes feasible connected partners by grid distance, then lowest commission, with random tie-breaking. An external sponsor can cover a configurable share of commission costs; its cash spending is recorded separately.

The model tracks deposit and withdrawal success, requested and served transaction values, low-balance exposure, and pending and completed peer trades. These measure access to mobile-money services; the model does not simulate a complete economy of household spending.

## Networks

**Synthetic random** generates an undirected Erdos–Renyi network from the chosen kiosk count and edge density. It runs without external data files.

**Observed mutual willingness** uses surveyed kiosk operators and their reported willingness to trade. An undirected tie exists only when both operators report willingness to trade with each other. These are stated-willingness ties, rather than records of actual trades. Operators with no mutual ties remain in the network.

**Imported synthetic** loads pre-generated graphs from `synthetic-networks/`, using the same node-and-edge format as observed networks. This supports graph ensembles generated outside NetLogo, with their generation settings and seeds recorded alongside them. Synthetic libraries can be included in the repository. Real survey exports in `data/` remain excluded from Git.

**GitHub synthetic** downloads the public [920-graph library](https://github.com/gabemgem/mobile-bank-markets/tree/main/synthetic-networks) in desktop NetLogo or NetLogo Web. It includes pooled primary and corrected hub sensitivity graphs at every size from 2–24 kiosks.

See the [network data guide](https://github.com/gabemgem/mobile-bank-markets/blob/main/experiments/NETWORKS.md) for file formats, provenance, and import instructions.

The [structural ERGM pipeline](https://github.com/gabemgem/mobile-bank-markets/blob/main/experiments/ERGM_NETWORKS.md) fits mutual willingness-to-trade networks and generates synthetic ensembles for import, with separate fitting diagnostics and reproducible graph seeds.
The [synthetic network generation guide](synthetic-networks/) explains the pooled primary generator, corrected hub sensitivity networks, repeated draws across kiosk counts, and desktop/Web loading options.

## Experiments and results

The experiment harness supports three complementary designs:

| Design | Purpose |
| --- | --- |
| One at a time (OAT) | Vary one parameter around a shared baseline while holding the others fixed. |
| Latin hypercube (LHS) | Explore joint variation across multiple parameter ranges. |
| Grid | Compare every combination of selected parameter levels. |

Repeated simulation seeds capture variation in synthetic networks and customer demand. The [results dashboard](results/) displays numerical response curves, scatter plots, and heatmaps, together with parameter settings and variation across seeds. Performance benchmarks help estimate study runtime before larger experiments.

The [liquidity policy pilot](results/policy-pilot/) compares network sharing,
external rebalancing and commission subsidies, with paired outcomes across synthetic
networks and measured runtime estimates for larger studies.

The [experiment guide](https://github.com/gabemgem/mobile-bank-markets/blob/main/experiments/RUNNING.md) explains benchmarking, configuring studies, running and resuming batches, and exporting aggregate results. The original OAT/LHS/grid configurations use v1 and synthetic random networks. The `v2-*` configurations select v2 explicitly and use the public synthetic library. No survey data are required.

## Run the model

1. For desktop **NetLogo 7.0.3**, run `python scripts/install_netlogo_fetch.py` once to install the official Fetch extension, then open [MobileBankMarkets_v2.nlogox](https://github.com/gabemgem/mobile-bank-markets/blob/main/MobileBankMarkets_v2.nlogox).
2. Choose **Synthetic random** to run without data, or select **Imported synthetic** / **Observed mutual willingness** and use **Choose local network**. For **GitHub synthetic**, use **Load GitHub library**.
3. Set the controls, click **Setup**, and use **Step**, **Go / stop**, or **+100 ticks**.

Press **Setup** after changing controls to start a new run. The model's Info tab documents transaction accounting, trade timing, parameters, and assumptions. Local imports and the experiment harness use desktop NetLogo.

In NetLogo Web, use **Load GitHub library** near the bottom of the interface. Wait for **Ready: 920 GitHub graphs**, select a **GitHub network ID** from the dropdown in v2, then click **Setup**. IDs are ordered by generator, kiosk count and replicate; `pooled-n20-r01` means pooled generator, 20 kiosks, replicate 1. V1 uses a text field for the ID. The **Use random networks** button returns to data-free simulation. The [generation guide](synthetic-networks/) explains URL pinning and download handling.

## Interpretation

The model is an abstract policy experiment. Initial balances, customer demand, and trading behavior are illustrative rather than calibrated estimates of surveyed markets. Loading an observed network changes the topology; it does not make the financial behavior empirical. V2 uses network-derived spring positions as synthetic geography, rather than measured locations. Changing topology can therefore change both connectivity and assumed travel distances.

Comparisons examine when liquidity sharing improves service and how participation, topology, reserve requirements, and settlement delays limit its benefits. Demand is specified per market per tick, so comparisons across market sizes should also consider demand per kiosk. In v2, traffic and transaction-size distributions can differ across kiosks. Travel and opening cycles are scenario inputs in abstract ticks, without a calibrated mapping to minutes or days.
