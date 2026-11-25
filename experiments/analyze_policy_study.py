"""Validate completed synthetic policy runs and export graph-level paired summaries."""
import argparse
from collections import Counter, defaultdict
import csv
import datetime as dt
import hashlib
import json
import math
from pathlib import Path
import statistics as stats

import policy_study as study
import run_experiments as h

LABELS = {'isolated':'Isolated', 'external':'External only', 'network-s0':'Network · no subsidy',
          'network-s50':'Network · 50% subsidy', 'network-s100':'Network · 100% subsidy',
          'fallback-s0':'Network + external · no subsidy', 'fallback-s50':'Network + external · 50% subsidy',
          'fallback-s100':'Network + external · 100% subsidy'}
CONTRASTS = {
    'external_vs_isolated': ('External access vs isolation', {'external':1, 'isolated':-1}),
    'network_vs_isolated': ('Network sharing vs isolation', {'network-s0':1, 'isolated':-1}),
    'fallback_vs_isolated': ('Sharing + fallback vs isolation', {'fallback-s0':1, 'isolated':-1}),
    'add_external': ('Add external fallback to sharing', {'fallback-s0':1, 'network-s0':-1}),
    'add_network': ('Add sharing to external access', {'fallback-s0':1, 'external':-1}),
    'network_half': ('50% subsidy vs unsubsidized sharing', {'network-s50':1, 'network-s0':-1}),
    'network_full': ('100% subsidy vs unsubsidized sharing', {'network-s100':1, 'network-s0':-1}),
    'network_full_vs_half': ('100% vs 50% subsidy, sharing', {'network-s100':1, 'network-s50':-1}),
    'fallback_half': ('50% subsidy vs unsubsidized fallback', {'fallback-s50':1, 'fallback-s0':-1}),
    'fallback_full': ('100% subsidy vs unsubsidized fallback', {'fallback-s100':1, 'fallback-s0':-1}),
    'fallback_full_vs_half': ('100% vs 50% subsidy, fallback', {'fallback-s100':1, 'fallback-s50':-1}),
    'interaction': ('Joint gain minus sum of standalone gains', {'fallback-s0':1, 'network-s0':-1, 'external':-1, 'isolated':1})
}
COUNTERS = ['requested_count','served_count','deposit_requested_value','withdrawal_requested_value',
            'deposit_served_value','withdrawal_served_value','closure_failed_count','closure_failed_value',
            'cash_failed_count','efloat_failed_count','trades_started','trades_settled','external_started',
            'external_settled','commissions_earned','commissions_paid','subsidy_spent','net_external_cash']
EXTRA = ['n_kiosks','n_links','final_cash','final_efloat']
FIELDS = sorted(set(h.V1_METRICS + h.V2_METRICS + COUNTERS + EXTRA))
METRICS = ['service_pct','deposit_service_pct','withdrawal_service_pct','request_service_pct',
           'closed_pct','closure_failure_pct','cash_failure_pct','efloat_failure_pct','subsidy_per_kiosk',
           'commission_per_kiosk','subsidy_spent','commissions_paid','served_value','requested_value',
           'peer_trades_per_kiosk','external_trades_per_kiosk','pending_per_kiosk','gain_pp',
           'deposit_gain_pp','withdrawal_gain_pp']


def ratio(numerator, denominator):
    return numerator / denominator if denominator > 0 else None


def close(a, b, context):
    if not math.isfinite(a) or not math.isfinite(b) or abs(a-b) > 1e-5:
        raise ValueError(f'{context}: {a} != {b}')


def validate_snapshot(row, n, tick, starting):
    close(row['n_kiosks'], n, 'Kiosk count')
    requested = row['deposit_requested_value'] + row['withdrawal_requested_value']
    served = row['deposit_served_value'] + row['withdrawal_served_value']
    close(row['service_pct'], 100*served/requested, 'Value service percentage')
    close(row['requested_count']-row['served_count'], row['closure_failed_count']+row['cash_failed_count']+row['efloat_failed_count'], 'Failure counts')
    close(row['commissions_earned'], row['commissions_paid']+row['subsidy_spent'], 'Commission ledger')
    customer_cash = row['deposit_served_value']-row['withdrawal_served_value']
    close(row['final_cash'], n*starting+customer_cash+row['net_external_cash']+row['subsidy_spent'], 'Cash ledger')
    close(row['final_efloat'], n*starting-customer_cash-row['net_external_cash'], 'E-float ledger')
    close(row['trades_started']-row['trades_settled'], row['pending_trades'], 'Peer pending count')
    close(row['external_started']-row['external_settled'], row['external_pending'], 'External pending count')
    for name in ['closed_share','cash_low_share','efloat_low_share']:
        if not 0 <= row[name] <= 1+1e-10:
            raise ValueError(f'Invalid {name} at {tick}')


def outcome(row, n, tick, previous=None, previous_tick=0):
    before = previous or dict.fromkeys(COUNTERS, 0)
    delta = {name: row[name]-before[name] for name in COUNTERS}
    if any(delta[name] < -1e-6 for name in COUNTERS if name != 'net_external_cash'):
        raise ValueError('Cumulative counter decreased')
    requested = delta['deposit_requested_value']+delta['withdrawal_requested_value']
    served = delta['deposit_served_value']+delta['withdrawal_served_value']
    closed = row['closed_share']*tick - (previous['closed_share']*previous_tick if previous else 0)
    return {'service_pct':100*ratio(served, requested),
            'deposit_service_pct':None if not delta['deposit_requested_value'] else 100*ratio(delta['deposit_served_value'],delta['deposit_requested_value']),
            'withdrawal_service_pct':None if not delta['withdrawal_requested_value'] else 100*ratio(delta['withdrawal_served_value'],delta['withdrawal_requested_value']),
            'request_service_pct':100*ratio(delta['served_count'],delta['requested_count']),
            'closed_pct':100*closed/(tick-previous_tick),
            'closure_failure_pct':100*delta['closure_failed_count']/delta['requested_count'],
            'cash_failure_pct':100*delta['cash_failed_count']/delta['requested_count'],
            'efloat_failure_pct':100*delta['efloat_failed_count']/delta['requested_count'],
            'subsidy_per_kiosk':delta['subsidy_spent']/n, 'commission_per_kiosk':delta['commissions_paid']/n,
            'subsidy_spent':delta['subsidy_spent'], 'commissions_paid':delta['commissions_paid'],
            'served_value':served, 'requested_value':requested,
            'peer_trades_per_kiosk':delta['trades_settled']/n,
            'external_trades_per_kiosk':delta['external_settled']/n,
            'pending_per_kiosk':(row['pending_trades']+row['external_pending'])/n}


class Mean:
    def __init__(self):
        self.total = Counter()
        self.count = Counter()

    def add(self, values):
        for key, value in values.items():
            if value is not None:
                self.total[key] += value
                self.count[key] += 1

    def values(self):
        return {key:self.total[key]/self.count[key] for key in self.total}


def quantile(values, p):
    ordered = sorted(values)
    index = (len(ordered)-1)*p
    low = math.floor(index)
    return ordered[low] + (index-low)*(ordered[math.ceil(index)]-ordered[low])


def aggregate(rows, keys, metrics=METRICS):
    groups = defaultdict(list)
    for row in rows:
        groups[tuple(row[k] for k in keys)].append(row)
    result = []
    for group, sample in groups.items():
        record = dict(zip(keys, group)) | {'graphs':len(sample)}
        for metric in metrics:
            values = [r[metric] for r in sample if r.get(metric) is not None]
            record[metric] = stats.mean(values) if values else None
        for metric in ['service_pct','gain_pp']:
            values = [r[metric] for r in sample if r.get(metric) is not None]
            if values:
                record[metric+'_graph_sd'] = stats.stdev(values) if len(values)>1 else 0
                record[metric+'_q10'] = quantile(values,.1)
                record[metric+'_q90'] = quantile(values,.9)
        if 'gain_pp' in record:
            changes = [r['gain_pp'] for r in sample]
            record['harm_pct'] = 100*sum(d < -.1 for d in changes)/len(changes)
            record['large_harm_pct'] = 100*sum(d < -1 for d in changes)/len(changes)
            record['improvement_pct'] = 100*sum(d > .1 for d in changes)/len(changes)
        if 'delta_subsidy' in record:
            cost = sum(r['delta_subsidy'] for r in sample)
            record['additional_value_per_subsidy_unit'] = ratio(sum(r['delta_value'] for r in sample),cost)
        result.append(record)
    return result


def csv_write(path, rows):
    if not rows:
        raise ValueError(f'No data for {path.name}')
    with path.open('w', newline='', encoding='utf-8') as target:
        writer = csv.DictWriter(target, fieldnames=list(rows[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)


def same(value, saved):
    if isinstance(value, bool):
        return saved.lower() == str(value).lower()
    if isinstance(value,(int,float)):
        return float(saved) == value
    return saved == str(value)


def analyze(root, out):
    spec, catalog, identity = study.load(study.DEFAULT)
    plan = json.loads((root/'plan.json').read_text())
    if plan['fingerprint'] != identity['fingerprint']:
        raise ValueError('Study inputs differ from the frozen plan')
    meta = {r['network_id']:r for r in catalog}
    graph_rows = []
    checked = Counter({'error_attempts':0,'duplicate_attempts':0,'duplicate_snapshots':0})
    for batch in plan['batches']:
        folder = root/'batches'/batch['batch']
        manifest = json.loads((folder/'manifest.json').read_text())
        if manifest['config'] != study.executor_config(spec,identity):
            raise ValueError(f'Unexpected configuration: {batch["batch"]}')
        for name, digest in manifest['sha256'].items():
            if study.digest(h.ABM/Path(name)) != digest:
                raise ValueError(f'Changed batch input: {name}')
        selected = study.graphs(spec,catalog,batch['generator'],batch['size'])
        expected = {r['run_id']:r for r in study.batch_design(spec,selected)}
        with (folder/'design.csv').open(newline='',encoding='utf-8') as source:
            design = list(csv.DictReader(source))
        if len(design)!=len(expected) or {r['run_id'] for r in design} != set(expected):
            raise ValueError('Incomplete or duplicate design')
        for saved in design:
            if any(not same(value,saved[key]) for key,value in expected[saved['run_id']].items()):
                raise ValueError('Saved design differs from planned controls')
        h.select_model('v2')
        attempts = h.read_attempts(folder/'attempts.csv')
        if set(attempts)!=set(expected) or any(r['status']!='ok' for r in attempts.values()):
            raise ValueError('Missing or failed final runs')
        with (folder/'attempts.csv').open(newline='',encoding='utf-8') as source:
            raw = list(csv.DictReader(source))
        checked['error_attempts'] += sum(r['status']=='error' for r in raw)
        checked['duplicate_attempts'] += len(raw)-len(attempts)
        history = {}
        with (folder/'trajectories.csv').open(newline='',encoding='utf-8') as source:
            for row in csv.DictReader(source):
                if None in row:
                    raise ValueError('Malformed trajectory record')
                key = row['run_id'],int(row['tick'])
                if key[0] not in expected or key[1] not in spec['checkpoints']:
                    raise ValueError('Unplanned trajectory record')
                if key in history:
                    checked['duplicate_snapshots'] += 1
                if row['active_market'] != expected[key[0]]['selected-market'] or not row['network_type'].startswith('synthetic-'):
                    raise ValueError('Non-synthetic or mismatched provenance')
                numeric = {name:float(row[name]) for name in FIELDS}
                if not all(math.isfinite(v) for v in numeric.values()):
                    raise ValueError('Non-finite trajectory metric')
                history[key] = numeric
        if len(history)!=len(expected)*len(spec['checkpoints']):
            raise ValueError('Incomplete trajectories')
        means = defaultdict(Mean)
        requests = {}
        for run_id, design_row in expected.items():
            previous = None
            previous_tick = 0
            graph = design_row['selected-market']
            for tick in spec['checkpoints']:
                row = history[run_id,tick]
                validate_snapshot(row,batch['size'],tick,spec['base']['starting-balance'])
                close(row['n_links'],float(meta[graph]['n_links']),'Link count')
                close(row['requested_count'],tick*design_row['requests-per-tick'],'Requested count')
                demand_key = graph,design_row['model-seed'],tick
                demand = tuple(row[k] for k in ['requested_count','deposit_requested_value','withdrawal_requested_value'])
                if demand_key in requests and requests[demand_key]!=demand:
                    raise ValueError('Customer requests differ across paired policies')
                requests[demand_key] = demand
                for mode in ['cumulative','interval']:
                    values = outcome(row,batch['size'],tick,previous if mode=='interval' else None,
                                     previous_tick if mode=='interval' else 0)
                    means[graph,design_row['policy_id'],mode,tick].add(values)
                previous,previous_tick = row,tick
                checked['snapshots'] += 1
            final = history[run_id,spec['ticks']]
            if any(final[name]!=float(attempts[run_id][name]) for name in FIELDS):
                raise ValueError('Final snapshot differs from saved run result')
            checked['runs'] += 1
        for (graph,policy,mode,tick), acc in means.items():
            if acc.count['service_pct'] != len(spec['seeds']):
                raise ValueError('Unbalanced seed replication')
            graph_rows.append({'network_id':graph,'generator':batch['generator'],'n':batch['size'],
                               'fit_id':meta[graph]['fit_id'],'policy':policy,'mode':mode,'tick':tick} | acc.values())
        checked['batches'] += 1
        print(f"Validated {batch['batch']}: {checked['runs']:,} runs, {checked['snapshots']:,} snapshots",flush=True)
    reference = {(r['network_id'],r['mode'],r['tick']):r for r in graph_rows if r['policy']=='isolated'}
    for row in graph_rows:
        baseline = reference[row['network_id'],row['mode'],row['tick']]
        for metric, change in [('service_pct','gain_pp'),('deposit_service_pct','deposit_gain_pp'),('withdrawal_service_pct','withdrawal_gain_pp')]:
            row[change] = row[metric]-baseline[metric] if row.get(metric) is not None and baseline.get(metric) is not None else None
    final = [r for r in graph_rows if r['mode']=='cumulative' and r['tick']==spec['ticks']]
    indexed = {(r['network_id'],r['policy']):r for r in final}
    contrasts = []
    for graph in sorted(reference_key[0] for reference_key in reference if reference_key[1:] == ('cumulative',spec['ticks'])):
        for name,(_,terms) in CONTRASTS.items():
            sample = [(weight,indexed[graph,policy]) for policy,weight in terms.items()]
            contrasts.append({'network_id':graph,'generator':sample[0][1]['generator'],'n':sample[0][1]['n'],
                'contrast':name,'gain_pp':sum(w*r['service_pct'] for w,r in sample),
                'delta_value':sum(w*r['served_value'] for w,r in sample),
                'delta_subsidy':sum(w*r['subsidy_spent'] for w,r in sample),
                'delta_subsidy_per_kiosk':sum(w*r['subsidy_per_kiosk'] for w,r in sample)})
    overall = aggregate(graph_rows,['generator','policy','mode','tick'])
    by_size = aggregate(final,['generator','n','policy'])
    comparison_metrics = ['gain_pp','delta_value','delta_subsidy','delta_subsidy_per_kiosk']
    comparisons = aggregate(contrasts,['generator','contrast'],comparison_metrics)
    comparisons_by_size = aggregate(contrasts,['generator','n','contrast'],comparison_metrics)
    fit_results = aggregate(final,['generator','fit_id','policy'])
    networks = []
    for graph in sorted({r['network_id'] for r in final}):
        original = meta[graph]
        networks.append({'network_id':graph,'generator':original['generator'],'n':int(original['n_nodes']),
            'fit_id':original['fit_id'],'density':float(original['density']),
            'isolate_pct':100*float(original['n_isolates'])/int(original['n_nodes']),
            'components':int(original['n_components']),'clustering':float(original['clustering']),
            'max_degree':int(original['max_degree']),
            'network_gain':indexed[graph,'network-s0']['gain_pp'],
            'fallback_gain':indexed[graph,'fallback-s0']['gain_pp'],
            'external_gain':indexed[graph,'external']['gain_pp']})
    status = json.loads((root/'background-status.json').read_text(encoding='utf-8-sig'))
    if status['state'] != 'complete' or set(status['completed_batches']) != {b['batch'] for b in plan['batches']}:
        raise ValueError('The supervisor has not completed the planned study')
    elapsed = (dt.datetime.fromisoformat(status['updated_utc'].replace('Z','+00:00'))-
               dt.datetime.fromisoformat(status['started_utc'].replace('Z','+00:00'))).total_seconds()
    report = {'version':1,'kind':'completed-synthetic-policy-study','model_version':'v2',
              'model_sha256':identity['sha256']['MobileBankMarkets_v2.nlogox'],
              'study_fingerprint':identity['fingerprint'],'analyzed_utc':dt.datetime.now(dt.timezone.utc).isoformat(),
              'analysis_sha256':study.digest(Path(__file__)),
              'checks':dict(checked),'elapsed_seconds':elapsed,'settings':spec,
              'policies':LABELS,'contrast_labels':{k:v[0] for k,v in CONTRASTS.items()},
              'harm_threshold_pp':-.1,
              'weighting':'Equal graph weights after averaging the same 20 seeds; equal size weights within each generator. Families reported separately.',
              'variation':'10th–90th percentiles and SD across seed-averaged graph outcomes; not confidence intervals or independent empirical markets.',
              'overall':overall,'by_size':by_size,'contrasts':comparisons,
              'contrasts_by_size':comparisons_by_size,'bootstrap_groups':fit_results,'networks':networks}
    out.mkdir(parents=True,exist_ok=True)
    study.save_json(out/'analysis.json',report)
    csv_write(out/'outcomes.csv',overall)
    csv_write(out/'size-outcomes.csv',by_size)
    csv_write(out/'contrasts.csv',comparisons)
    csv_write(out/'size-contrasts.csv',comparisons_by_size)
    csv_write(out/'graph-outcomes.csv',final)
    csv_write(out/'network-structure.csv',networks)
    csv_write(out/'bootstrap-groups.csv',fit_results)
    print(json.dumps({'checks':report['checks'],'final_policy_means':[
        {k:r[k] for k in ['generator','policy','service_pct','gain_pp','harm_pct','subsidy_per_kiosk']}
        for r in overall if r['tick']==spec['ticks'] and r['mode']=='cumulative']},indent=2))
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root',type=Path)
    parser.add_argument('--out',type=Path,required=True)
    args = parser.parse_args()
    analyze(args.root,args.out)
