# Model versions and v2 policy experiments

Two versions share the same network format and accounting foundation:

- **[V1](../MobileBankMarkets_v1.nlogox)** preserves the abstract model: equal
  initial working capital, uniform customer traffic, alternating deposit/withdrawal
  tendencies, proactive peer swaps, reserved balances and 0–2 tick settlement.
- **[V2](../MobileBankMarkets_v2.nlogox)** adds external rebalancing, unequal
  customer traffic and transaction sizes, service interruption during trips, spring/grid geography, supplier commissions and optional commission subsidies.

V1 remains the unchanged simple sandbox. V2 is the policy model with different spatial matching rules. Neither is calibrated to predict numerical policy effects. The
synthetic networks represent mutual stated willingness to trade, not actual
transactions, geography or empirically measured travel times.

## V2 mechanisms

### External rebalancing

An external provider exchanges cash and e-float at equal value. It has ample
resources but supplies **no grant, loan or new working capital**. A kiosk buying
cash must pay with its available e-float; selling cash reverses the exchange.
The kiosk must preserve `minimum-reserve` in its outgoing resource. Each exchange
is capped by `external-max-amount`, the desired refill and the kiosk's budget. This separate provider does not charge the peer commission.

External access is a fixed random assignment independent of peer participation.
It is not inferred from network degree or a kiosk's location. Access assignments
are nested as the percentage increases, for a fixed seed/population. The external
provider's capacity and queue do not respond to other kiosks' use. Opening hours
determine when a trade can be booked; booked trades settle even after closing.

| `external-mode` | Behavior |
| --- | --- |
| `Disabled` | Only the selected peer-sharing policy operates. |
| `External only` | Peer trades are disabled; kiosks with access may rebalance externally. |
| `Peers then external` | Try a feasible peer trade, then external service if none can be booked. |

A partial peer refill prevents an additional external booking in that tick.
`No sharing` suppresses peers, not external access. Consequently, use `External
only` to compare peer sharing with a replenishment option, and `Disabled` plus
`No sharing` for the completely isolated abstract comparator. Peer matching still
assumes perfect knowledge of eligible partners' available balances.

### Heterogeneous demand

The fixed `requests-per-tick` total is allocated across kiosks by synthetic
lognormal traffic weights. A second independent lognormal multiplier changes
the transaction-size distribution at each kiosk. Profiles remain fixed for a run.

- `demand-heterogeneity = 0` gives uniform kiosk selection.
- `size-heterogeneity = 0` gives the same transaction-size distribution everywhere.
- Positive values are standard deviations on the log scale, not percentages or
  estimated survey coefficients.
- Size multipliers are normalized using traffic weights. Expected market-wide
  transaction size remains that of the base uniform `1..maximum-request`
  distribution. Individual requests can exceed `maximum-request` when size
  heterogeneity is positive. Realized batches still fluctuate.
- Existing `withdrawal-share` and `demand-polarization` set alternating kiosk
  tendencies, clipped to probabilities between zero and one. With unequal traffic,
  `withdrawal-share` is not a guaranteed aggregate withdrawal percentage.

Demand remains exogenous: closed shops still receive their original requests,
which fail. There are no retries, rerouting, customer queues, time-varying shocks,
or household agents. Policy comparisons retain the same original requests when
demand settings, seed and population are held fixed.

### Travel and shop closure

A peer swap completes after its **Manhattan grid distance** in ticks. An external
exchange completes after `external-travel-ticks + external-service-delay`.
Travel is an abstract round-trip duration; the external service delay includes
waiting and processing. A tick is a customer-demand batch, with no calibrated
mapping to minutes. The illustrative opening cycle is not an observed working day.

With `travel-closes-shop? = true`, the requester closes for the peer grid-distance
interval, or for the full external travel/service interval. The peer supplier
stays open. With the switch off, staff can handle the trip while service continues;
reservations still constrain available balances. There is at most one pending
exchange per kiosk and at most one new booking per kiosk per tick.

At tick `t`, due exchanges settle first, then kiosks assess low balances, then the
customer batch is served. A trade of duration `d` booked at `t` settles at `t+d`
before that batch. A zero-duration exchange settles immediately. For example,
external travel 2 plus service 1 affects batches `t`, `t+1`, `t+2` and settles
before batch `t+3`. A peer three grid steps away takes three ticks and closes the requester for those
three demand batches. Same-square trades settle immediately.

## Added controls and defaults

Defaults are illustrative scenarios, not empirical estimates. The pre-existing
threshold, target, reserve, initial-balance and demand controls retain their roles.

| Parameter | V2 default | Meaning |
| --- | --- | --- |
| `external-mode` | `Peers then external` | Rebalancing strategy above. |
| `external-access-percent` | 100 | Probability each kiosk can access the provider. |
| `external-travel-ticks` | 3 | Round-trip external travel. |
| `external-service-delay` | 1 | External queue/processing delay. |
| `external-max-amount` | 500 | Maximum value of one external exchange. |
| `external-open-ticks` | 8 | Open booking ticks at the start of each cycle. |
| `external-cycle-ticks` | 12 | Repeating cycle length. Open ticks must not exceed it. |
| `grid-cell-size` | 5 | Whole patch widths per square (1–33); larger squares generally shorten grid travel. |
| `travel-closes-shop?` | true | Whether trips interrupt customer service. |
| `demand-heterogeneity` | 1 | Log traffic-weight standard deviation. |
| `size-heterogeneity` | 0.5 | Log transaction-size multiplier standard deviation. |

## Spring/grid geography and partner choice

Setup initializes positions on a circle, then runs NetLogo's
[`layout-spring`](https://docs.netlogo.org/7.0.3/dictionary#layout-spring) for
200 iterations with spring strength 0.2, spring length 4 and repulsion 1. It centers
and uniformly scales the result to leave a two-patch display margin. All
relationship links participate, independently of the sharing policy. Positions
are fixed during a run. A separate seeded stream ensures the same graph/seed
has the same positions across commission, subsidy, demand and grid-size settings.
The algorithm tends to cluster tightly connected agents. It is synthetic geography,
not evidence about actual kiosk locations or measured travel times.

Grid squares are anchored at the southwest world boundary (-16.5, -16.5).
Coordinates exactly on a boundary belong to its north/east cell. Distance is
`abs(column difference) + abs(row difference)`: 0 in the same cell, 1 for a
horizontal/vertical neighbor, 2 for a diagonal. The displayed lines/checkerboard
show the partition. A cell size of 33 places the entire world in one square.
The distance itself is the total trip/settlement duration; there is no extra
return multiplier or fixed peer settlement delay. The old v2 `settlement-delay`
and `peer-travel-ticks` controls are removed; v1 retains its original controls.

For peer trades, filter out unavailable suppliers and quotes that cannot fund a
positive refill while preserving outgoing reserves and paying the requester fee.
Partial refills remain successful trades even when they cannot reach the target.
Rank feasible suppliers by **grid distance, then commission rate**, and choose
randomly among exact ties across equally near cells. A cheaper farther supplier
does not displace a feasible nearer one. Network sharing requires an existing
tie; all-to-all sharing relaxes that constraint. The external-mode strategy still
determines whether external rebalancing is a fallback; it does not compare a
feasible peer's price/time against the external provider.

Changing graph topology changes spring positions as well as eligibility. Therefore
a density/topology experiment measures both connectivity and assumed geography.
Hold graph and seed fixed when isolating commission/subsidy/grid policy effects.
V2 no longer claims exact recovery of v1 trajectories: nearest-partner selection
intentionally differs from v1's random matching, even with zero commissions.

## Cash commissions and subsidy accounting

| Parameter | Default | Meaning |
| --- | --- | --- |
| `commission-mode` | `Uniform` | Same rate for everyone, or `Varied` rates drawn once per run. |
| `commission-percent` | 1 | Percentage of gross exchanged liquidity in Uniform mode. |
| `commission-min-percent` | 0.5 | Lower bound in Varied mode. |
| `commission-max-percent` | 1.5 | Upper bound in Varied mode; equal bounds give one rate. |
| `commission-subsidy-percent` | 0 | Share of the fee paid by an external sponsor (0–100%). |

Varied rates are independent uniform draws, held fixed for a run, not fitted
preferences. The default varied range has the same expected rate as Uniform 1%.
Agents charge their own rate when supplying either cash or e-float. The fee base
is **gross exchanged value**, excluding the fee itself. All rates must be >=0
and <100%; the interface offers 0–50%. The subsidy has no aggregate budget cap.

For a gross swap `q`, supplier rate `r`, and subsidy fraction `s`:

- Total cash commission is `r*q`; requester pays `(1-s)*r*q` and sponsor pays `s*r*q`.
- Cash buyers pay from incoming cash, receiving `q - requester fee`. Gross desired
  refill accounts for this deduction, subject to the buyer's e-float budget and
  supplier's available cash above reserve.
- E-float buyers must afford and reserve `q + requester fee` in cash. The supplier
  reserves `q` e-float. The cash budget thus caps `q` at `budget / (1+(1-s)*r)`.
- Amount, fee and subsidy are fixed at booking, paid once at settlement. The
  sponsor covers the quoted share; pending subsidies are commitments, not spending.

Fees transfer capital from requester to supplier. Only sponsor payments add cash
to the local market. Accounting enforces `supplier income = requester payments +
subsidy spending` and includes subsidy spending in the market cash ledger. E-float
is unaffected by commission payments. The policy effect combines lower requester
costs and additional cash; it should not be described as a pure information or
matching intervention. No credit, bargaining, endogenous participation or other
operating costs are included.

## Outputs and visual interpretation

The model retains deposit/withdrawal value served, transaction counts, shortages,
reservations and peer trade metrics. V2 also records:

- External exchanges started, settled, pending, and their gross values.
- Signed `net-external-cash`: positive means net cash purchased from the provider;
  equal e-float leaves the local market. Market accounting includes this flow.
- Closed kiosk-ticks and their share of all kiosk-ticks.
- Customer failures due to closure, insufficient cash, or insufficient e-float.
  These causes are mutually exclusive and reconcile with total failed requests.
- Requested value lost during closure.

Gray squares show closed shops; purple circles show other external-pending kiosks.
Amber arrows remain peer transfers. The external pipeline plot separates bookings
from settlements. The interruption plot shows the cumulative mean number of
closed kiosks per completed batch. Spring/grid positions are synthetic geography, not observed locations.

The harness keeps existing trade-count/value columns **peer-only** and adds
`external_started`, `external_settled`, `external_value`, `external_pending`,
`external_pending_value`, `net_external_cash`, `closed_share`,
`closure_failed_count`, `closure_failed_value`, `cash_failed_count`, and
`efloat_failed_count`, plus `commissions_earned`, `commissions_paid`, `subsidy_spent`,
`pending_commissions`, `pending_subsidy`, and `mean_peer_distance`. Reservation totals
include both types of exchange and cash fees payable by e-float buyers. Gross settled
liquidity excludes commissions. Kiosk-level `earned-commissions` and `paid-commissions`
allow inspection of who receives or bears the charges.

## Running versioned experiments

Run from `ABM/`. Install the desktop Fetch extension once:

```powershell
python scripts/install_netlogo_fetch.py
```

Configs select a model using `"model_version": "v1"` or `"v2"`. An omitted version
defaults to v1 for older configurations. All original bundled configurations now
name v1 explicitly. The manifest records the filename, version and source hash;
resuming a run after changing model/configuration/harness remains prohibited.
Old performance profiles require a fresh benchmark after this harness update.

Start small:

```powershell
python experiments/run_experiments.py experiments/configs/v2-smoke.json --out results/v2-smoke
python experiments/performance.py --model-version v2 --ticks 20 80 --repeats 1 --out results/performance-v2
```

The 12-run smoke design uses both synthetic generators at 12 kiosks, three
external modes and two demand seeds. It checks operation, not policy superiority.
The 12 measured benchmark runs plus two warm-ups use built-in random networks
at cell sizes 2, 5 and 33 with other v2 mechanisms at their defaults. Its timing estimates concern that workload; they are
not a calibrated bound for different opening hours, travel or external policies.
Time a small subset at the intended settings before a large library sweep.

Prepared studies use the public `pooled-n12-r01` graph and five demand seeds:

| Configuration | Design | Runs |
| --- | --- | --- |
| `v2-oat.json` | Threshold, external travel/access, demand, grid size, commission rate and subsidy around one baseline. | 100 |
| `v2-grid.json` | External travel × threshold × external-only/peer-first strategy. | 90 |
| `v2-lhs.json` | 24 joint settings for access, travel, refill cap, threshold, demand, staffing, grid and commissions. | 120 |

```powershell
python experiments/run_experiments.py experiments/configs/v2-grid.json --out results/v2-grid --dry-run
# Inspect design.csv before execution, then:
python experiments/run_experiments.py experiments/configs/v2-grid.json --out results/v2-grid --resume
```

Library studies run from local `synthetic-networks/`; asynchronous GitHub loading
is for the interactive model. The current performance estimator and public-report
exporter accept only built-in `Synthetic random` designs. Imported synthetic runs
still produce local CSV summaries and paired OAT effects/rank sensitivity outputs.
For a random-network v2 study, change `network-source` to `Synthetic random` and
`selected-market` to an empty string. Exported reports record v2; existing site
reports remain v1 results and are not rerun or relabeled as new policy evidence.

The prepared studies explore one graph; they do not establish robustness across
network structure. For substantive comparisons, add matched graph IDs from both
generators and compare the same policy settings on each graph with the same
demand seeds. Report variation across graphs separately from within-graph seeds.

A dedicated `v2-commission-grid.json` compares grid size × Uniform/Varied fees ×
subsidy share (90 runs, five seeds), with matched expected fee rates. Start with
`v2-spatial-smoke.json` (16 runs, two seeds) before that study. These configurations
use the public pooled library. They generate local summaries; no results are
automatically published or interpreted as empirical forecasts.

## Verification

`tests/run-checks.ps1` runs the legacy v1 regressions, data-free/widget-free checks
and HTTP loader checks for both versions, plus v2 accounting/timing/mechanism and
spatial/commission/subsidy checks. A fixed SHA-256 verifies that v1 is unchanged. Add `-FullLibrary` to import all 920 graphs in each version.
Python harness tests run with:

```powershell
python -m unittest discover -s experiments -p "test_*.py"
```

Raw surveys, observed exports and fitted objects remain private and ignored.
No survey file or project PDF is embedded in either model or uploaded by a
random-network run. Policy inputs remain assumptions to vary, not fitted effects.
