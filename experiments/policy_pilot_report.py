"""Check the synthetic policy pilot and estimate serial runtimes from its timing sample."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import statistics as stats

import run_experiments as h


def complete(folder):
    manifest = json.loads((folder / 'manifest.json').read_text())
    config = json.loads((folder / 'config.json').read_text())
    if config.get('model_version') != 'v2':
        raise ValueError('Expected a v2 study')
    h.select_model('v2')
    for name, digest in manifest['sha256'].items():
        if hashlib.sha256((h.ABM / name).read_bytes()).hexdigest() != digest:
            raise ValueError(f'Study input changed: {name}')
    with (folder / 'design.csv').open(newline='', encoding='utf-8') as source:
        design = list(csv.DictReader(source))
    attempts = h.read_attempts(folder / 'attempts.csv')
    if set(attempts) != {r['run_id'] for r in design} or any(r['status'] != 'ok' for r in attempts.values()):
        raise ValueError('Complete successful runs are required')
    with (h.ABM / 'synthetic-networks/networks.csv').open(newline='', encoding='utf-8') as source:
        public_ids = {r['network_id'] for r in csv.DictReader(source)}
    if any(r['network-source'] != 'Imported synthetic' or r['selected-market'] not in public_ids for r in design):
        raise ValueError('Only public imported synthetic networks are supported')
    rows = [r | attempts[r['run_id']] for r in design]
    if any(r['active_market'] != r['selected-market'] or not r['network_type'].lower().startswith('synthetic') for r in rows):
        raise ValueError('Result network provenance does not match the design')
    return config, rows


def estimate(folder, config, rows, planned_runs, ticks):
    measured_ticks = config['ticks']
    costs = [float(r['setup_seconds']) + float(r['metrics_seconds']) +
             float(r['simulation_seconds']) * ticks / measured_ticks for r in rows]
    timing = json.loads((folder / 'timing.json').read_text())
    engine = json.loads((folder / 'engine_timing.json').read_text())
    startup = max(0, timing['compile_seconds'] + timing['engine_wall_seconds'] -
                  sum(float(r['seconds']) for r in rows) - engine['warmup_seconds'])
    warmup = engine['warmup_seconds'] * max(1, ticks / measured_ticks)
    return {'runs': planned_runs, 'ticks': ticks,
            'estimated_seconds': startup + warmup + planned_runs * stats.mean(costs),
            'planning_seconds': startup + warmup + planned_runs * max(1.5 * stats.mean(costs), max(costs)),
            'extrapolated_horizon': ticks != measured_ticks}


def compare(rows):
    index = {(r['selected-market'], r['model-seed'], r['sharing-mode'], r['external-mode'],
              int(r['commission-subsidy-percent'])): r for r in rows}
    pairs = sorted({(r['selected-market'], r['model-seed']) for r in rows})
    # Subsidies must be inert when peers are disabled, and external-only ignores peer eligibility.
    checks = 0
    for market, seed in pairs:
        for sharing in ['No sharing', 'Network sharing']:
            for external in ['Disabled', 'External only', 'Peers then external']:
                if sharing == 'Network sharing' and external != 'External only':
                    continue
                baseline = index[market, seed, sharing, external, 0]
                for subsidy in [50, 100]:
                    candidate = index[market, seed, sharing, external, subsidy]
                    for metric in h.METRICS:
                        if abs(float(candidate[metric]) - float(baseline[metric])) > 1e-8:
                            raise ValueError(f'Inactive subsidy changed {metric}: {market}, seed {seed}')
                    checks += 1
        for sharing, external in [('Network sharing', 'External only'), ('No sharing', 'Peers then external')]:
            for metric in h.METRICS:
                if abs(float(index[market, seed, sharing, external, 0][metric]) -
                       float(index[market, seed, 'No sharing', 'External only', 0][metric])) > 1e-8:
                    raise ValueError(f'Equivalent external policies differ: {metric}')
            checks += 1
    for market, seed in pairs:
        group = [r for r in rows if r['selected-market'] == market and r['model-seed'] == seed]
        for field in ['requested_count', 'deposit_requested_value', 'withdrawal_requested_value']:
            if len({r[field] for r in group}) != 1:
                raise ValueError('Customer requests changed across paired policies')
    for row in rows:
        if abs(float(row['commissions_earned']) - float(row['commissions_paid']) - float(row['subsidy_spent'])) > 1e-6:
            raise ValueError('Fee accounting failed')
    arms = [('Isolated', 'No sharing', 'Disabled', 0),
            ('External only', 'No sharing', 'External only', 0)]
    arms += [(f'Network + {s}% subsidy', 'Network sharing', 'Disabled', s) for s in [0, 50, 100]]
    arms += [(f'Network + external + {s}% subsidy', 'Network sharing', 'Peers then external', s) for s in [0, 50, 100]]
    summary = []
    for market_group in ['All'] + sorted({m for m, _ in pairs}):
        selected = [(m, s) for m, s in pairs if market_group == 'All' or m == market_group]
        for label, sharing, external, subsidy in arms:
            sample = [index[m, s, sharing, external, subsidy] for m, s in selected]
            baseline = [index[m, s, 'No sharing', 'Disabled', 0] for m, s in selected]
            delta = [float(a['service_pct']) - float(b['service_pct']) for a, b in zip(sample, baseline)]
            record = {'network': market_group, 'policy': label, 'paired_runs': len(sample),
                      'service_change_pp_mean': stats.mean(delta), 'service_change_pp_sd': stats.stdev(delta)}
            for metric in ['service_pct', 'deposit_service_pct', 'withdrawal_service_pct', 'closed_share',
                           'trades_settled', 'external_settled', 'subsidy_spent', 'commissions_paid', 'mean_peer_distance']:
                values = [float(r[metric]) for r in sample]
                record[metric + '_mean'] = stats.mean(values)
                record[metric + '_sd'] = stats.stdev(values)
            summary.append(record)
    return summary, checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('timing', type=Path)
    parser.add_argument('--plan', type=Path, default=h.ABM / 'experiments/configs/v2-policy-pilot.json')
    parser.add_argument('--pilot', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    config, rows = complete(args.timing)
    plan = json.loads(args.plan.read_text(encoding='utf-8-sig'))
    design, rejected = h.build_design(plan)
    if rejected or config['base'] != plan['base'] or any(
            config['parameters'][name] != values for name, values in plan['parameters'].items() if name != 'selected-market'):
        raise ValueError('Timing and planned policy settings must match; rerun timing after changing settings')
    args.out.mkdir(parents=True, exist_ok=True)
    estimates = [estimate(args.timing, config, rows, len(design), plan['ticks'])]
    estimates += [estimate(args.timing, config, rows, n, t) for n in [1000, 10000] for t in [200, 1000]]
    report = {'model_version': 'v2', 'model_sha256': hashlib.sha256(h.MODEL.read_bytes()).hexdigest(),
              'timing_runs': len(rows), 'estimates': estimates,
              'caveat': 'Serial, machine-specific planning estimates. Based on two synthetic graphs and two seeds at 200 ticks. '
                        'Planning uses the larger of 1.5 times mean cost and the slowest measured run cost. '
                        'Longer horizons scale simulation time linearly; different graph structures or workloads need new timing. '
                        'No statistical confidence bounds or parallel speedup are implied.'}
    if args.pilot:
        pilot_config, pilot = complete(args.pilot)
        if pilot_config != plan:
            raise ValueError('Pilot does not match planned configuration')
        summary, checks = compare(pilot)
        h.write_csv(args.out / 'policy_summary.csv', summary)
        report['completed_pilot_runs'] = len(pilot)
        report['equivalent_policy_checks'] = checks
        measured = json.loads((args.pilot / 'timing.json').read_text())
        report['pilot_wall_seconds'] = measured['compile_seconds'] + measured['engine_wall_seconds']
    (args.out / 'runtime_estimates.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
