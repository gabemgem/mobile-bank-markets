"""Prepare a batched v2 study, benchmark it, and estimate costs before explicit batch execution."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import random
import re
import statistics as stats

import run_experiments as h

DEFAULT = h.ABM / 'experiments/configs/v2-policy-study.json'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save_json(path, data):
    path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8', newline='\n')


def load(path):
    spec = json.loads(path.read_text(encoding='utf-8-sig'))
    expected = {'version', 'ticks', 'checkpoints', 'seeds', 'warmup_runs', 'sizes', 'generators',
                'graphs_per_size', 'requests_per_kiosk', 'base', 'policies', 'benchmark'}
    if set(spec) != expected or spec['version'] != 1:
        raise ValueError('Unknown study configuration fields or version')
    if spec['base'].get('network-source') != 'Imported synthetic':
        raise ValueError('This study requires the public synthetic library')
    ids = [p['id'] for p in spec['policies']]
    if not ids or len(set(ids)) != len(ids) or any(not re.fullmatch('[a-z0-9-]+', p) for p in ids):
        raise ValueError('Policies need unique lowercase IDs')
    if len(set(spec['sizes'])) != len(spec['sizes']) or any(type(n) is not int or not 2 <= n <= 24 for n in spec['sizes']):
        raise ValueError('Use distinct sizes within 2–24')
    if len(set(spec['generators'])) != len(spec['generators']) or not set(spec['generators']) <= {'pooled', 'corrected_hub'}:
        raise ValueError('Unknown or duplicated synthetic generator')
    if type(spec['graphs_per_size']) is not int or not 1 <= spec['graphs_per_size'] <= 20:
        raise ValueError('graphs_per_size must be 1–20')
    if type(spec['requests_per_kiosk']) is not int or spec['requests_per_kiosk'] < 1:
        raise ValueError('requests_per_kiosk must be a positive integer')
    with (h.ABM / 'synthetic-networks/networks.csv').open(newline='', encoding='utf-8') as source:
        catalog = list(csv.DictReader(source))
    if len({r['network_id'] for r in catalog}) != len(catalog):
        raise ValueError('Duplicate synthetic network IDs')
    files = [h.ABM/'MobileBankMarkets_v2.nlogox', Path(__file__), Path(h.__file__),
             h.ABM/'experiments/BatchRunner.java']
    files += [h.ABM/'synthetic-networks'/f for f in ['networks.csv', 'nodes.csv', 'edges.csv']]
    hashes = {p.relative_to(h.ABM).as_posix(): digest(p) for p in files}
    identity = {'study': spec, 'sha256': hashes}
    identity['fingerprint'] = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
    return spec, catalog, identity


def graphs(spec, catalog, generator, size):
    rows = sorted((r for r in catalog if r['generator'] == generator and int(r['n_nodes']) == size),
                  key=lambda r: int(r['replicate']))
    rows = rows[:spec['graphs_per_size']]
    if len(rows) != spec['graphs_per_size']:
        raise ValueError(f'Missing graphs for {generator}, n={size}')
    return rows


def batch_design(spec, selected, ticks=None, seeds=None):
    ticks = ticks or spec['ticks']
    seeds = spec['seeds'] if seeds is None else seeds
    size = int(selected[0]['n_nodes'])
    if any(int(r['n_nodes']) != size for r in selected):
        raise ValueError('A batch must have one kiosk count')
    rows = []
    for policy in spec['policies']:
        settings = {k: v for k, v in policy.items() if k != 'id'}
        cfg = {'model_version': 'v2', 'mode': 'grid', 'ticks': ticks, 'seeds': seeds,
               'checkpoints': [t for t in spec['checkpoints'] if t <= ticks],
               'base': spec['base'] | settings | {'requests-per-tick': size * spec['requests_per_kiosk']},
               'parameters': {'selected-market': [selected[0]['network_id']]}}
        prototypes, rejected = h.build_design(cfg)
        if rejected:
            raise ValueError('Study contains invalid points')
        for graph_index, graph in enumerate(selected):
            point = f"{policy['id']}-g{graph_index:02d}"
            for prototype in prototypes:
                rows.append(prototype | {'run_id': f"{point}-s{prototype['model-seed']}", 'point_id': point,
                    'selected-market': graph['network_id'], 'policy_id': policy['id'],
                    'generator': graph['generator'], 'catalog_density': float(graph['density']),
                    'n_nodes': size, 'fit_id': graph['fit_id']})
    return rows


def executor_config(spec, identity, ticks=None, seeds=None):
    horizon = ticks or spec['ticks']
    return {'model_version': 'v2', 'mode': 'grid', 'ticks': horizon,
            'checkpoints': [t for t in spec['checkpoints'] if t <= horizon],
            'seeds': seeds if seeds is not None else spec['seeds'], 'parameters': {},
            'warmup_runs': spec['warmup_runs'], 'study_identity': identity}


def prepare(spec, catalog, identity, out):
    path = out / 'plan.json'
    if out.exists() and any(out.iterdir()) and (not path.exists() or json.loads(path.read_text())['fingerprint'] != identity['fingerprint']):
        raise ValueError('Plan directory is nonempty or inputs changed; choose a new directory')
    batches = []
    for generator in spec['generators']:
        for size in spec['sizes']:
            selected = graphs(spec, catalog, generator, size)
            design = batch_design(spec, selected)
            if len(design) > 50000 or len({r['run_id'] for r in design}) != len(design):
                raise ValueError('Invalid batch size or duplicate run IDs')
            batches.append({'batch': f'{generator}-n{size:02d}', 'generator': generator, 'size': size,
                            'graphs': len(selected), 'runs': len(design), 'requests_per_tick': size * spec['requests_per_kiosk']})
    out.mkdir(parents=True, exist_ok=True)
    plan = identity | {'planned_runs': sum(b['runs'] for b in batches), 'batches': batches,
                       'status': 'prepared; no full-study runs launched'}
    save_json(path, plan)
    h.write_csv(out / 'batches.csv', batches)
    print(f"Prepared {len(batches)} batches, {plan['planned_runs']:,} runs; no simulations launched.", flush=True)
    return plan


def benchmark_design(spec, catalog):
    bench = spec['benchmark']
    if not set(bench['sizes']) <= set(spec['sizes']) or not set(bench['seeds']) <= set(spec['seeds']):
        raise ValueError('Benchmark sizes/seeds must be in the study')
    rows = []
    for generator in spec['generators']:
        for size in bench['sizes']:
            ordered = sorted(graphs(spec, catalog, generator, size), key=lambda r: (float(r['density']), r['network_id']))
            for role, graph in [('sparse', ordered[0]), ('dense', ordered[-1])]:
                for horizon in bench['ticks']:
                    for row in batch_design(spec, [graph], horizon, bench['seeds']):
                        prefix = f'{generator}-n{size:02d}-{role}-t{horizon}-'
                        rows.append(row | {'run_id': prefix + row['run_id'], 'point_id': prefix + row['point_id'],
                                          'benchmark_role': role})
    random.Random(bench['order_seed']).shuffle(rows)
    return rows


def check_measurements(folder, sample, checkpoints):
    history = {}
    with (folder/'trajectories.csv').open(newline='', encoding='utf-8') as source:
        for row in csv.DictReader(source):
            if None not in row and row.get('run_id') and row.get('tick'):
                history[row['run_id'], int(row['tick'])] = row
    requests = {}
    measured = 0
    for row in sample:
        expected_count = row['ticks'] * row['requests-per-tick']
        if float(row['requested_count']) != expected_count or float(row['n_kiosks']) != row['n_nodes']:
            raise ValueError('Measured population or request count differs from design')
        key = row['selected-market'], row['model-seed'], row['ticks']
        value = tuple(row[name] for name in ['requested_count', 'deposit_requested_value', 'withdrawal_requested_value'])
        if key in requests and requests[key] != value:
            raise ValueError('Original requests changed across policies')
        requests[key] = value
        if abs(float(row['commissions_earned']) - float(row['commissions_paid']) - float(row['subsidy_spent'])) > 1e-6:
            raise ValueError('Fee ledger does not reconcile')
        for tick in sorted(set([t for t in checkpoints if t <= row['ticks']] + [row['ticks']])):
            snapshot = history[row['run_id'], tick]
            if float(snapshot['requested_count']) != tick * row['requests-per-tick']:
                raise ValueError('Trajectory request counts do not match its tick')
            measured += 1
        final = history[row['run_id'], row['ticks']]
        if any(float(final[name]) != float(row[name]) for name in h.METRICS):
            raise ValueError('Final trajectory snapshot differs from final result')
    return measured


def estimate(spec, catalog, identity, benchmark, plan):
    manifest = json.loads((benchmark/'manifest.json').read_text())
    if manifest['config']['study_identity'] != identity:
        raise ValueError('Benchmark does not match the current study/model/runner/library')
    design = benchmark_design(spec, catalog)
    h.select_model('v2')
    attempts = h.read_attempts(benchmark/'attempts.csv')
    if set(attempts) != {r['run_id'] for r in design} or any(r['status'] != 'ok' for r in attempts.values()):
        raise ValueError('A complete successful benchmark is required')
    sample = [row | attempts[row['run_id']] for row in design]
    snapshots = check_measurements(benchmark, sample, spec['checkpoints'])
    target = [r for r in sample if r['ticks'] == spec['ticks']]
    if not target:
        raise ValueError('Benchmark must measure the exact study horizon; do not extrapolate')
    timings = json.loads((benchmark/'timing.json').read_text())
    overhead = max(0, timings['compile_seconds'] + timings['engine_wall_seconds'] - sum(float(r['seconds']) for r in sample))
    groups = {}
    for row in target:
        key = row['generator'], row['n_nodes'], row['policy_id'], row['benchmark_role']
        groups.setdefault(key, []).append(float(row['seconds']))
    sizes = sorted(spec['benchmark']['sizes'])
    if min(sizes) > min(spec['sizes']) or max(sizes) < max(spec['sizes']):
        raise ValueError('Benchmark sizes must bracket study sizes')
    estimates = []
    for batch in plan['batches']:
        generator, size = batch['generator'], batch['size']
        selected = graphs(spec, catalog, generator, size)
        low = max(n for n in sizes if n <= size)
        high = min(n for n in sizes if n >= size)
        size_weight = 0 if high == low else (size-low)/(high-low)
        density_min = min(float(r['density']) for r in selected)
        density_max = max(float(r['density']) for r in selected)
        expected = allowance = 0
        for graph in selected:
            weight = ((float(graph['density'])-density_min)/(density_max-density_min)) if density_max > density_min else .5
            for policy in spec['policies']:
                means = []
                measured = []
                for n in [low, high]:
                    sparse = groups[generator, n, policy['id'], 'sparse']
                    dense = groups[generator, n, policy['id'], 'dense']
                    means.append((1-weight)*stats.mean(sparse) + weight*stats.mean(dense))
                    measured.extend(sparse + dense)
                cost = (1-size_weight)*means[0] + size_weight*means[1]
                expected += len(spec['seeds']) * cost
                allowance += len(spec['seeds']) * max(1.5*cost, max(measured))
        estimates.append(batch | {'estimated_seconds': expected + overhead, 'planning_seconds': allowance + overhead})
    horizon_summary = []
    for horizon in sorted({r['ticks'] for r in sample}):
        part = [r for r in sample if r['ticks'] == horizon]
        horizon_summary.append({'ticks': horizon, 'runs': len(part),
            'mean_run_seconds': stats.mean(float(r['seconds']) for r in part),
            'max_run_seconds': max(float(r['seconds']) for r in part)})
    report = {'model_version': 'v2', 'study_fingerprint': identity['fingerprint'],
              'model_sha256': identity['sha256']['MobileBankMarkets_v2.nlogox'],
              'measured_runs': len(sample), 'benchmark_wall_seconds': timings['compile_seconds'] + timings['engine_wall_seconds'],
              'verified_snapshots': snapshots,
              'horizons': horizon_summary, 'planned_runs': plan['planned_runs'], 'batches': estimates,
              'estimated_seconds': sum(b['estimated_seconds'] for b in estimates),
              'planning_seconds': sum(b['planning_seconds'] for b in estimates),
              'full_study_started': False,
              'method': 'Exact measured horizon and policy; interpolate size and within-size density position. '
                        'Charge measured compilation/startup/warm-up overhead once per batch. '
                        'Planning uses at least 1.5x interpolated run costs and the slowest relevant measured run.',
              'caveat': 'Serial, machine-specific planning estimates, not confidence bounds or a maximum. '
                        'Only two seeds and density endpoints per benchmark size; intermediate graph structure and background load can change costs.'}
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'benchmark', 'estimate', 'run'])
    parser.add_argument('--config', type=Path, default=DEFAULT)
    parser.add_argument('--out', type=Path, required=True, help='Study plan and future batch root')
    parser.add_argument('--benchmark-out', type=Path)
    parser.add_argument('--batch', help='Explicit batch ID; required for run')
    parser.add_argument('--resume', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--netlogo-home', type=Path, default=Path('C:/Program Files/NetLogo 7.0.3'))
    parser.add_argument('--java'); parser.add_argument('--javac')
    args = parser.parse_args()
    spec, catalog, identity = load(args.config)
    if args.action == 'prepare':
        prepare(spec, catalog, identity, args.out)
        return
    plan = json.loads((args.out/'plan.json').read_text())
    if plan['fingerprint'] != identity['fingerprint']:
        raise ValueError('Study inputs changed; prepare a new plan directory')
    if args.action in {'benchmark', 'estimate'} and not args.benchmark_out:
        raise ValueError('--benchmark-out is required')
    if args.action == 'benchmark':
        design = benchmark_design(spec, catalog)
        cfg = executor_config(spec, identity, max(spec['benchmark']['ticks']), spec['benchmark']['seeds'])
        # Include every measurement boundary used by the full study, plus the longest test horizon.
        cfg['checkpoints'] = sorted(set(spec['checkpoints'] + [max(spec['benchmark']['ticks'])]))
        args.out = args.benchmark_out
        raise SystemExit(h.execute_design(cfg, design, [], args))
    if args.action == 'estimate':
        report = estimate(spec, catalog, identity, args.benchmark_out, plan)
        save_json(args.out/'runtime-estimates.json', report)
        h.write_csv(args.out/'runtime-by-batch.csv', report['batches'])
        print(json.dumps({k: v for k, v in report.items() if k != 'batches'}, indent=2))
        return
    batch = next((b for b in plan['batches'] if b['batch'] == args.batch), None)
    if batch is None:
        raise ValueError('Use --batch with an explicit ID from batches.csv; no automatic full-study launch')
    design = batch_design(spec, graphs(spec, catalog, batch['generator'], batch['size']))
    args.out = args.out/'batches'/batch['batch']
    raise SystemExit(h.execute_design(executor_config(spec, identity), design, [], args))


if __name__ == '__main__':
    main()
