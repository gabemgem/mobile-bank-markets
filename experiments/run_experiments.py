"""Reproducible OAT, factorial-grid, and Latin-hypercube experiments (stdlib only)."""
from __future__ import annotations

import argparse
import base64
import csv
import hashlib
import itertools
import json
import math
from pathlib import Path
import random
import shutil
import statistics
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

ABM = Path(__file__).resolve().parents[1]
MODEL = ABM / 'MobileBankMarkets.nlogox'
METRICS = ['service_pct', 'deposit_service_pct', 'withdrawal_service_pct', 'served_count',
           'trades_started', 'trades_settled', 'pending_trades', 'settled_value', 'pending_value',
           'reserved_cash', 'reserved_efloat', 'unmet_attempts', 'cash_low_share', 'efloat_low_share']


def write_csv(path, rows, columns=None):
    rows = list(rows)
    columns = columns or (list(rows[0]) if rows else [])
    with path.open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader(); writer.writerows(rows)


def controls():
    # These are code globals; keep private network IDs out of saved UI widgets.
    defaults = {'network-source': 'Synthetic random', 'selected-market': ''}
    schema = {'network-source': {'kind':'choice','values':
              ['Synthetic random','Observed mutual willingness','Imported synthetic']},
              'selected-market': {'kind':'text'}}
    for w in ET.parse(MODEL).find('widgets'):
        name = w.get('variable')
        if not name:
            continue
        if name.startswith('ui-'):
            name = name[3:]
        if w.tag == 'slider':
            integer = float(w.get('step')).is_integer() and float(w.get('min')).is_integer()
            cast = int if integer else float
            defaults[name] = cast(float(w.get('default')))
            schema[name] = {'kind': 'number', 'min': float(w.get('min')), 'max': float(w.get('max')),
                            'integer': integer}
        elif w.tag == 'chooser':
            choices = [c.get('value') for c in w]
            defaults[name] = choices[int(w.get('current'))]
            schema[name] = {'kind': 'choice', 'values': choices}
        elif w.tag == 'switch':
            defaults[name] = w.get('on') == 'true'
            schema[name] = {'kind': 'bool'}
    return defaults, schema


def validate_value(name, value, schema):
    if name not in schema:
        raise ValueError(f'Unknown model control: {name}')
    s = schema[name]
    if s['kind'] == 'choice':
        valid = value in s['values']
    elif s['kind'] == 'bool':
        valid = isinstance(value, bool)
    elif s['kind'] == 'text':
        valid = isinstance(value, str)
    else:
        valid = (isinstance(value, (int, float)) and not isinstance(value, bool)
                 and math.isfinite(value) and s['min'] <= value <= s['max']
                 and (not s['integer'] or float(value).is_integer()))
    if not valid:
        raise ValueError(f'Invalid value for {name}: {value!r}; expected {s}')


def build_design(config):
    defaults, schema = controls()
    if not isinstance(config, dict):
        raise ValueError('Configuration must be a JSON object')
    allowed = {'mode', 'ticks', 'seeds', 'base', 'parameters', 'samples', 'design_seed', 'invalid_combinations', 'warmup_runs'}
    if set(config) - allowed:
        raise ValueError(f'Unknown configuration fields: {set(config) - allowed}')
    mode = config.get('mode', 'oat')
    if mode not in {'oat', 'grid', 'lhs'}:
        raise ValueError('mode must be oat, grid, or lhs')
    if type(config.get('warmup_runs',0)) is not int or not 0 <= config.get('warmup_runs',0) <= 10:
        raise ValueError('warmup_runs must be an integer between 0 and 10')
    ticks = config.get('ticks', 100)
    if type(ticks) is not int or ticks < 1:
        raise ValueError('ticks must be a positive integer')
    seeds = config.get('seeds', [11, 22, 33])
    if not isinstance(seeds, list) or not seeds:
        raise ValueError('seeds must be a nonempty list of distinct integers')
    for seed in seeds:
        validate_value('model-seed', seed, schema)
    if len(set(seeds)) != len(seeds):
        raise ValueError('seeds must be distinct')
    if not isinstance(config.get('base', {}), dict) or not isinstance(config.get('parameters', {}), dict):
        raise ValueError('base and parameters must be objects')
    base = defaults | config.get('base', {})
    parameters = config.get('parameters', {})
    if 'model-seed' in config.get('base', {}) or 'model-seed' in parameters:
        raise ValueError('Use seeds for stochastic replicates, not model-seed in base/parameters')
    for name, value in base.items():
        validate_value(name, value, schema)
    if mode == 'oat' and base['target-balance-percent'] <= base['low-balance-percent']:
        raise ValueError('OAT requires a valid baseline target above the trigger')
    if not parameters:
        raise ValueError('Specify at least one varied parameter')
    if 'show-balances?' in parameters:
        raise ValueError('Display settings are not sensitivity parameters')
    for name in parameters:
        if name not in schema:
            raise ValueError(f'Unknown model control: {name}')
    points = []
    if mode in {'oat', 'grid'}:
        for name, values in parameters.items():
            if not isinstance(values, list) or not values:
                raise ValueError(f'{name}: supply a nonempty list of values')
            if len({json.dumps(v) for v in values}) != len(values):
                raise ValueError(f'{name}: duplicate sweep levels')
            for value in values:
                validate_value(name, value, schema)
        if mode == 'oat':
            points.append(('baseline', base.copy()))
            for name, values in parameters.items():
                points.extend((name, base | {name: value}) for value in values if value != base[name])
        else:
            count = math.prod(len(v) for v in parameters.values()) * len(seeds)
            if count > 50000:
                raise ValueError(f'Grid would create {count} runs; limit is 50,000 per design')
            points = [('joint', base | dict(zip(parameters, values)))
                      for values in itertools.product(*parameters.values())]
    else:
        n = config.get('samples', 50)
        if type(n) is not int or not 1 <= n <= 50000 // len(seeds):
            raise ValueError('Invalid samples or more than 50,000 runs')
        rng = random.Random(config.get('design_seed', 20261114))
        sampled = {}
        for name, spec in parameters.items():
            if not isinstance(spec, dict):
                raise ValueError(f'{name}: LHS needs {{min,max}} or {{values:[...]}}')
            if set(spec) == {'values'}:
                choices = spec['values']
                if not isinstance(choices, list) or not choices:
                    raise ValueError(f'{name}: empty categorical levels')
                for value in choices:
                    validate_value(name, value, schema)
                values = [choices[min(len(choices)-1, int((i+rng.random())/n*len(choices)))] for i in range(n)]
            elif set(spec) == {'min', 'max'} and schema[name]['kind'] == 'number':
                lo, hi = spec['min'], spec['max']
                validate_value(name, lo, schema); validate_value(name, hi, schema)
                if lo > hi:
                    raise ValueError(f'{name}: min exceeds max')
                if schema[name]['integer']:
                    values = [min(int(hi), int(lo) + int((i+rng.random())/n*(hi-lo+1))) for i in range(n)]
                else:
                    values = [round(lo+(i+rng.random())/n*(hi-lo), 8) for i in range(n)]
            else:
                raise ValueError(f'{name}: unsupported LHS specification {spec}')
            rng.shuffle(values); sampled[name] = values
        points = [('joint', base | {name: values[i] for name, values in sampled.items()}) for i in range(n)]
    rejected, accepted = [], []
    for index, (varied, point) in enumerate(points):
        for name, value in point.items():
            validate_value(name, value, schema)
        reason = None
        if point['target-balance-percent'] <= point['low-balance-percent']:
            reason = 'Refill target must exceed low-balance trigger'
        elif point['network-source'] != 'Synthetic random' and any(
            name in parameters for name in ['number-of-kiosks', 'network-density']):
            reason = 'Kiosk count and density are ignored for imported networks; do not sweep them'
        elif point['network-source'] == 'Synthetic random' and 'selected-market' in parameters:
            reason = 'selected-market is ignored for synthetic networks; do not sweep it'
        if reason:
            rejected.append({'point': index, 'reason': reason, 'parameters': point})
        else:
            if point['network-source'] != 'Synthetic random':
                folder = ABM / ('data' if point['network-source']=='Observed mutual willingness' else 'synthetic-networks')
                missing = [name for name in ['networks.csv','nodes.csv','edges.csv'] if not (folder/name).is_file()]
                if missing:
                    raise ValueError(f'Missing local import files in {folder}: {missing}. '
                                     'Synthetic random needs no data files')
                with (folder/'networks.csv').open(newline='',encoding='utf-8') as f:
                    catalog = list(csv.DictReader(f))
                ids = [r.get('network_id') for r in catalog]
                if not ids or any(not x for x in ids) or len(ids)!=len(set(ids)):
                    raise ValueError('Local catalog needs unique, nonempty network_id values')
                point['selected-market'] = point['selected-market'] or ids[0]
                if point['selected-market'] not in ids:
                    raise ValueError('Selected network ID is absent from the local catalog')
            accepted.append((varied, point))
    policy = config.get('invalid_combinations', 'error')
    if policy not in {'error', 'skip'}:
        raise ValueError('invalid_combinations must be error or skip')
    if rejected and policy == 'error':
        raise ValueError(f'{len(rejected)} invalid design points; first: {rejected[0]}. '
                         'Use invalid_combinations="skip" to explicitly exclude invalid points')
    if not accepted or len(accepted)*len(seeds) > 50000:
        raise ValueError('No valid points, or more than 50,000 runs')
    rows = []
    for index, (varied, point) in enumerate(accepted):
        for seed in seeds:
            rows.append({'run_id': f'p{index:05d}-s{int(seed)}', 'point_id': f'p{index:05d}',
                         'mode': mode, 'varied_parameter': varied, 'ticks': ticks,
                         **point, 'model-seed': int(seed)})
    return rows, rejected


def netlogo_literal(value):
    if isinstance(value, bool):
        return str(value).lower()
    return json.dumps(value, ensure_ascii=False)


def ranks(values):
    ordered = sorted(range(len(values)), key=values.__getitem__)
    result = [0.0]*len(values)
    i = 0
    while i < len(ordered):
        j = i+1
        while j < len(ordered) and values[ordered[j]] == values[ordered[i]]:
            j += 1
        for k in range(i, j):
            result[ordered[k]] = (i+j-1)/2
        i = j
    return result


def read_attempts(path):
    if not path.exists():
        return {}
    with path.open(newline='', encoding='utf-8') as f:
        latest = {}
        for row in csv.DictReader(f):
            if None in row or not row.get('run_id') or row.get('status') not in {'ok','error'}:
                continue
            if row['status'] == 'ok':
                try:
                    if not all(math.isfinite(float(row[m])) for m in METRICS):
                        continue
                except (ValueError, TypeError, KeyError):
                    continue
            latest[row['run_id']] = row
        return latest


def summarize(out, design, config):
    attempts = out/'attempts.csv'
    if not attempts.exists():
        return []
    latest = read_attempts(attempts)
    results = [{**d, **latest[d['run_id']]} for d in design if d['run_id'] in latest]
    write_csv(out/'results.csv', results)
    points = {}
    for row in results:
        points.setdefault(row['point_id'], []).append(row)
    summary = []
    for point_id, runs in points.items():
        ok = [r for r in runs if r['status'] == 'ok']
        fields = {k: v for k,v in runs[0].items() if k in design[0] and k not in {'run_id','model-seed'}}
        fields |= {'n_success': len(ok), 'n_error': len(runs)-len(ok),
                   'n_expected': len(config.get('seeds', [11,22,33]))}
        for metric in METRICS:
            values = [float(r[metric]) for r in ok]
            fields |= {metric+'_mean': statistics.mean(values) if values else '',
                       metric+'_sd': statistics.stdev(values) if len(values)>1 else '',
                       metric+'_min': min(values) if values else '',
                       metric+'_max': max(values) if values else ''}
        summary.append(fields)
    write_csv(out/'summary.csv', summary)
    if config.get('mode','oat') == 'oat':
        baseline = {r['model-seed']: r for r in results if r['varied_parameter']=='baseline' and r['status']=='ok'}
        effects = []
        for point_id, runs in points.items():
            if runs[0]['varied_parameter'] == 'baseline':
                continue
            matched = [(r, baseline[r['model-seed']]) for r in runs
                       if r['status']=='ok' and r['model-seed'] in baseline]
            for metric in METRICS:
                diffs = [float(r[metric])-float(b[metric]) for r,b in matched]
                effects.append({'point_id': point_id, 'parameter': runs[0]['varied_parameter'],
                    'value': runs[0][runs[0]['varied_parameter']], 'metric': metric,
                    'n_paired': len(diffs), 'paired_difference_mean': statistics.mean(diffs) if diffs else '',
                    'paired_difference_sd': statistics.stdev(diffs) if len(diffs)>1 else ''})
        write_csv(out/'oat_effects.csv', effects)
    else:
        effects = []
        defaults, schema = controls()
        for name in config['parameters']:
            if schema[name]['kind'] != 'number':
                continue
            for metric in METRICS:
                # Use complete design-point means, not seed repetitions as independent samples.
                usable = [s for s in summary if s['n_success']==s['n_expected'] and s[metric+'_mean']!='']
                x = ranks([float(s[name]) for s in usable])
                y = ranks([float(s[metric+'_mean']) for s in usable])
                rho = statistics.correlation(x,y) if len(x)>=3 and len(set(x))>1 and len(set(y))>1 else ''
                effects.append({'parameter': name, 'metric': metric, 'n_complete_points': len(x),
                                'spearman_rho': rho})
        write_csv(out/'rank_sensitivity.csv', effects,
                  ['parameter','metric','n_complete_points','spearman_rho'])
    return results


def find_executable(name):
    found = shutil.which(name)
    if not found:
        raise ValueError(f'{name} not found. Put a JDK on PATH or pass --{name} /path/to/{name}')
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--netlogo-home', type=Path, default=Path('C:/Program Files/NetLogo 7.0.3'))
    parser.add_argument('--java'); parser.add_argument('--javac')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--resume', action='store_true')
    parser.add_argument('--profile', type=Path, help='Estimate runtime from a measured performance profile')
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding='utf-8-sig'))
    design, rejected = build_design(config)
    if args.profile:
        from performance import estimate, format_estimate
        print(format_estimate(estimate(json.loads(args.profile.read_text()),design,config)),flush=True)
    return execute_design(config,design,rejected,args)


def execute_design(config, design, rejected, args):
    """Shared executor for normal studies and the small explicit benchmark design."""
    out = args.out.resolve()
    inputs = [MODEL, Path(__file__), Path(__file__).with_name('BatchRunner.java')]
    if config.get('mode')=='benchmark':
        inputs.append(Path(__file__).with_name('performance.py'))
    sources = {r['network-source'] for r in design}
    for source, folder in [('Observed mutual willingness','data'),('Imported synthetic','synthetic-networks')]:
        if source in sources:
            inputs.extend(ABM/folder/name for name in ['networks.csv','nodes.csv','edges.csv'])
    hashes = {str(p.relative_to(ABM)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    identity = {'config': config, 'sha256': hashes}
    fingerprint = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
    manifest = out/'manifest.json'
    if out.exists() and any(out.iterdir()):
        if not args.resume:
            raise ValueError('Output directory is nonempty. Choose a new directory or use --resume')
        if not manifest.exists() or json.loads(manifest.read_text())['fingerprint'] != fingerprint:
            raise ValueError('Resume refused: configuration, model, harness, or network data changed')
    out.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps({'fingerprint': fingerprint, **identity, 'planned_runs': len(design),
        'rejected_points': rejected}, indent=2), encoding='utf-8')
    write_csv(out/'design.csv', design)
    (out/'config.json').write_text(json.dumps(config,indent=2),encoding='utf-8')
    done = set()
    if (out/'attempts.csv').exists():
        latest = read_attempts(out/'attempts.csv')
        done = {k for k,v in latest.items() if v['status']=='ok'}
    pending = [d for d in design if d['run_id'] not in done]
    print(f'{len(design)} runs; {len(done)} successful checkpoints; {len(pending)} remaining; '
          f'{len(rejected)} invalid points excluded.', flush=True)
    if args.dry_run:
        print(f'Design saved to {out}; use --resume to execute it later.')
        return 0
    if pending:
        java, javac = args.java or find_executable('java'), args.javac or find_executable('javac')
        home = args.netlogo_home.resolve()
        if not (home/'app/netlogo-7.0.3.jar').is_file():
            raise ValueError('This harness is tested with NetLogo 7.0.3; check --netlogo-home')
        build = out/'classes'; build.mkdir(exist_ok=True)
        compile_start = time.perf_counter()
        subprocess.run([javac,'-cp',str(home/'app/*'),'-d',str(build),str(Path(__file__).with_name('BatchRunner.java'))],check=True)
        compile_seconds = time.perf_counter()-compile_start
        defaults, _ = controls()
        with (out/'work.tsv').open('w',encoding='utf-8',newline='\n') as f:
            for row in pending:
                commands = ' '.join(f'set {k} {netlogo_literal(row[k])}' for k in defaults)
                f.write(f"{row['run_id']}\t{row['ticks']}\t{base64.b64encode(commands.encode()).decode()}\n")
        import os
        attempts = out/'attempts.csv'
        if attempts.exists():
            data = attempts.read_bytes()
            if data and not data.endswith(b'\n'):
                # Each Java checkpoint occupies one physical line. Discard only a torn tail.
                boundary = data.rfind(b'\n')+1
                (out/'incomplete_checkpoint.bin').write_bytes(data[boundary:])
                attempts.write_bytes(data[:boundary])
        cmd = [java, f'-Dnetlogo.extensions.dir={home / "extensions"}', '-cp',
               str(build)+os.pathsep+str(home/'app/*'), 'BatchRunner', str(MODEL),
               str(out/'work.tsv'), str(out/'attempts.csv'), str(out/'engine_timing.json'),
               str(config.get('warmup_runs',0))]
        engine_start = time.perf_counter()
        with (out/'run.log').open('a',encoding='utf-8') as log:
            process = subprocess.Popen(cmd,cwd=ABM,stdout=log,stderr=subprocess.STDOUT)
            try:
                code = process.wait()
            except KeyboardInterrupt:
                process.terminate(); process.wait()
                summarize(out,design,config)
                print('Interrupted. Completed checkpoints retained; rerun with --resume.')
                return 130
        timing = {'compile_seconds': compile_seconds, 'engine_wall_seconds': time.perf_counter()-engine_start,
                  'attempted_runs':len(pending), 'warmup_runs':config.get('warmup_runs',0)}
        (out/'timing.json').write_text(json.dumps(timing,indent=2),encoding='utf-8')
        if code:
            print(f'Batch exited with code {code}; inspect run.log and per-run errors.',file=sys.stderr)
    results = summarize(out,design,config)
    success = sum(r['status']=='ok' for r in results)
    print(f'{success}/{len(design)} successful runs. Outputs: {out}',flush=True)
    return 0 if success==len(design) else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(f'Error: {exc}',file=sys.stderr)
        sys.exit(2)
