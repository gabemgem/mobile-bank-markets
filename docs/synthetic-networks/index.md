---
layout: default
title: Synthetic network generation
---

[Project](../) · [Experiment results](../results/)

# Synthetic networks for mobile-money markets

The model uses synthetic networks to explore how liquidity-sharing policies work
across plausible market structures. Each node represents a kiosk operator. An
undirected tie represents **mutual stated willingness to trade liquidity**. It
does not represent acquaintance alone or a recorded cash transfer. Operators
without ties remain in the graph.

## Two complementary generators

| Generator | Use in the ABM | Structural assumptions |
| --- | --- | --- |
| **Pooled degree-plus-closure ERGM** | Primary network ensemble | Market size affects tie propensity. Shared degree and closure terms describe uneven connectivity and triangles. |
| **Corrected hub model** | Structural sensitivity alternative | Adds latent operator activity, market-level density variation, and calibrated count/closure distributions. |

“Pooled” means that structural coefficients are estimated jointly across surveyed
markets. Markets remain separate networks; operators in different markets are
never linked. This statistical pooling is distinct from operators sharing cash
inside the ABM.

The pooled model was selected as the simpler primary generator after nested
internal validation. The corrected hub model remains useful for checking whether
policy conclusions change when high-degree operators are better represented.
Nested validation uses previously studied markets and is not fresh external
confirmation. Neither generator establishes the accuracy of the model's financial
behavior.

## From surveys to generated graphs

1. **Construct mutual ties.** Keep a tie only when both surveyed operators report
   willingness to trade with each other. Retain respondents with no mutual ties.
   Exclude self-links, cross-market links, and nominated nonrespondents. A missing
   reverse response produces no tie; it is not treated as an explicit refusal.
2. **Refit on all markets.** Fit both generator families on the complete set of
   observed market networks. The pooled ERGM includes edges, a size effect,
   geometrically weighted degree, and geometrically weighted edgewise shared
   partners (closure); both geometric decays are fixed at 0.5.
3. **Represent estimation uncertainty.** Refit both generators to four matched
   market-bootstrap samples. Resample whole markets, preserving each sampled
   market's complete graph. The all-market point fit is retained as a reference;
   the exported ensemble uses the four bootstrap fits with equal weight.
4. **Generate independently.** For each generator and every size from **2 to 24
   kiosks**, draw **20 networks**, five from each bootstrap fit. Each graph has its
   own generation seed. This gives 460 primary graphs and 460 sensitivity graphs.
5. **Audit and import.** Check simple undirected structure, node counts, edge
   endpoints, isolates, and catalog statistics. Load the graphs into NetLogo and
   check that their exact adjacencies and transaction accounting are preserved.

For pooled networks, the fitted ERGM generates both tie count and topology from
the supplied kiosk count. For corrected hub networks, a corrected density law
draws the tie count first. A conditional ERGM then arranges that many ties using
degree, closure, and generated latent activity. It preserves the sampled count
exactly. No held-out or observed market graph is used as a generated adjacency.

Latent activity is a random structural propensity, rather than an observed
operator attribute. The pipeline does not fit homophily. Generator coefficients,
calibration choices, seeds, and diagnostics are recorded separately from the ABM's
financial parameters.

## What varies—and what stays fixed

Size is fixed for each graph. Tie count, isolate count, component structure,
degree distribution, hubs, and triangles can vary between draws. Empty and complete
graphs are legitimate outcomes, particularly at the smallest sizes. The pipeline
does not discard a draw merely because its topology is inconvenient.

Network generation seeds control graph structure. Simulation seeds control
customer requests and other randomness inside NetLogo. Keep them separate and
compare liquidity-sharing policies on the same graph before moving to another
replicate. Loading a synthetic network does not calibrate demand, initial balances,
participation, reserves, or settlement delays.
Requests per tick are a market total: using the same setting at different sizes
changes demand per kiosk, which should be considered in comparisons.

The 2–24 range is the domain assessed by the empirical network work. Larger
networks can be explored as explicit extrapolations or with the model's built-in
random-network mode.

## Desktop NetLogo

The repository's `synthetic-networks/` library uses three CSV files:

| File | Contents |
| --- | --- |
| `networks.csv` | Anonymous graph ID, network type, generator, replicate, seed, fit ID, and realized statistics |
| `nodes.csv` | Every generated node, including isolates |
| `edges.csv` | One row per undirected edge |

In desktop NetLogo 7.0.3:

1. Open `MobileBankMarkets.nlogox` with the library in its neighboring
   `synthetic-networks/` directory.
2. Use **Network source → Imported synthetic**.
3. Use **Choose local network**, select a generator, kiosk count, and graph ID.
4. Click **Setup** and run the model.

IDs such as `pooled-n12-r03` and `corrected-hub-n12-r03` identify generator, size,
and replicate. The size and density sliders apply to built-in random networks;
an imported graph supplies its own node count and ties. The importer caches CSV
tables for repeated runs. Reopen the chooser or run `reload-network-library`
after replacing the files. Built-in random networks still work without any data.

## Load the published library in NetLogo Web

The [published library on GitHub](https://github.com/gabemgem/mobile-bank-markets/tree/main/synthetic-networks)
contains all 920 generated graphs. Download the three companion files:
[catalog](https://raw.githubusercontent.com/gabemgem/mobile-bank-markets/main/synthetic-networks/networks.csv),
[nodes](https://raw.githubusercontent.com/gabemgem/mobile-bank-markets/main/synthetic-networks/nodes.csv),
and [edges](https://raw.githubusercontent.com/gabemgem/mobile-bank-markets/main/synthetic-networks/edges.csv).
These live in the repository root; the Pages website serves its content from `docs/`.

The model's **GitHub synthetic** source works in NetLogo Web and desktop NetLogo.
It uses the **Fetch extension** to request all three CSVs, parses their text,
and validates the complete library before making it available to Setup.
NetLogo documents this distinction in its [Web extension
notes](https://netlogoweb.org/whats-new) and [Fetch extension
reference](https://github.com/NetLogo/Fetch-Extension).

1. [Open the model in NetLogo Web](https://netlogoweb.org/launch#https://raw.githubusercontent.com/gabemgem/mobile-bank-markets/main/MobileBankMarkets.nlogox).
2. Near the bottom of the interface, leave `ui-github-base-url` at its default and click **Load GitHub library**. This selects **GitHub synthetic** automatically.
3. Wait for **Ready: 920 GitHub graphs** in the status monitor.
4. Enter a graph ID in `ui-github-network-id`, for example `pooled-n20-r01` or `corrected-hub-n20-r01`, then click **Setup** and run.

The base URL identifies the directory, without a CSV filename. For reproducible
runs, replace `main` with a full commit SHA, for example:

```text
https://raw.githubusercontent.com/gabemgem/mobile-bank-markets/<commit>/synthetic-networks
```

Use raw URLs that allow browser cross-origin access; GitHub `blob` pages are HTML.
Changing the URL requires **Load GitHub library** again. Changing the graph ID
requires **Setup**, but reuses the downloaded library. The default public URLs
were tested in NetLogo Web on 16 November 2026: all 920 graphs downloaded, and
both example graphs completed 100 ticks with accounting checks.

**Cancel download** discards pending results; late responses cannot replace a
newer library. An incomplete, malformed, or failed library cannot be used by
Setup. Browser HTTP errors may also display NetLogo Web's standard error dialog;
the loader expires missing responses after 30 seconds when its monitor, Setup,
or Go checks the status. Retry with **Load GitHub library**, or use **Use random
networks** for data-free runs. Cancel invalidates responses rather than aborting
the browser's underlying requests.

Desktop NetLogo needs the official Fetch extension installed once with
`python scripts/install_netlogo_fetch.py` from the repository directory. The
installer pins Fetch 1.0.5 for compatibility with the Java 11 experiment harness
and verifies the official archive and JAR checksums. NetLogo Web supplies Fetch
itself. Desktop imports still use the local CSV folders; no remote request is
made in **Synthetic random** or either local-import mode.

## Reproducibility and data handling

The generated library contains anonymous node and graph labels, not respondent
IDs or copied market adjacencies. Small generated graphs can coincide with
observed shapes by chance. Synthetic generation does not by itself provide a
formal privacy guarantee.

Raw surveys, observed exports, fit objects, bootstrap memberships, and detailed
research diagnostics remain in private, ignored locations. Generated CSVs are
separately reviewable for publication. Public release of either CSVs or a model
with embedded resources is separate from private estimation.

See the [generation commands and configuration](https://github.com/gabemgem/mobile-bank-markets/blob/main/experiments/GENERATE_ABM_NETWORKS.md)
and [nested validation design](https://github.com/gabemgem/mobile-bank-markets/blob/main/experiments/NESTED_NETWORK_VALIDATION.md)
for the reproducible pipeline.
