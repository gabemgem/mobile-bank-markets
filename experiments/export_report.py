"""Prepare a public report from COMPLETE ABSTRACT SYNTHETIC runs only; never publish."""
import argparse
import csv
import datetime as dt
import json
from pathlib import Path
import re
import sys
import run_experiments as h


def build_report(folder, slug, title):
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,63}',slug):
        raise ValueError('Report id must use lowercase letters, numbers, and hyphens')
    manifest=json.loads((folder/'manifest.json').read_text())
    config=json.loads((folder/'config.json').read_text())
    h.select_model(config.get('model_version', 'v1'))
    if config.get('mode') not in {'oat','lhs','grid'}:
        raise ValueError('Benchmark reports are separate from scientific experiment results')
    if any(k.startswith(('data/','synthetic-networks/')) for k in manifest['sha256']):
        raise ValueError('Imported network studies cannot be exported by this public-report tool')
    with (folder/'design.csv').open(newline='',encoding='utf-8') as f: design=list(csv.DictReader(f))
    if not design or any(r['network-source']!='Synthetic random' or r['selected-market'] for r in design):
        raise ValueError('Only abstract Synthetic random designs with no local network ID are allowed')
    attempts=h.read_attempts(folder/'attempts.csv')
    if set(attempts)!= {r['run_id'] for r in design} or any(r['status']!='ok' for r in attempts.values()):
        raise ValueError('Complete successful runs are required; resume failures/missing runs first')
    if any(r.get('active_market') or not r.get('network_type','').startswith('Synthetic:') for r in attempts.values()):
        raise ValueError('Result network provenance is not purely abstract synthetic')
    with (folder/'summary.csv').open(newline='',encoding='utf-8') as f: summary=list(csv.DictReader(f))
    if any(int(r['n_success'])!=int(r['n_expected']) for r in summary):
        raise ValueError('Summary has incomplete seed replication')
    _,schema=h.controls()
    points=[]
    for row in summary:
        params={}
        for name,spec in schema.items():
            if name in {'selected-market','show-balances?','model-seed'}: continue
            value=row[name]
            if spec['kind']=='number': value=float(value)
            params[name]=value
        metrics={metric:{stat:float(row[metric+'_'+stat]) if row[metric+'_'+stat]!='' else None
                         for stat in ['mean','sd','min','max']} for metric in h.METRICS}
        points.append({'id':row['point_id'],'varied':row['varied_parameter'],
                       'replicates':int(row['n_success']),'parameters':params,'metrics':metrics})
    extra='oat_effects.csv' if config['mode']=='oat' else 'rank_sensitivity.csv'
    with (folder/extra).open(newline='',encoding='utf-8') as f: sensitivity=list(csv.DictReader(f))
    # Whitelist numeric sensitivity outputs; no paths, raw network IDs, logs, or free-text errors.
    clean=[]
    for row in sensitivity:
        record={k:row[k] for k in ['point_id','parameter','metric'] if k in row}
        for key in ['value','n_paired','paired_difference_mean','paired_difference_sd','n_complete_points','spearman_rho']:
            if key in row:
                try: record[key]=float(row[key]) if row[key]!='' else None
                except ValueError: record[key]=str(row[key]) if row['parameter']=='sharing-mode' else None
        clean.append(record)
    return {'version':1,'id':slug,'title':title,'mode':config['mode'],
            'network_source':'Synthetic random','ticks':config['ticks'],
            'seeds':config.get('seeds',[11,22,33]),'warmup_runs':config.get('warmup_runs',0),
            'balance_labels':design[0]['show-balances?'].lower()=='true',
            'replicates':len(config.get('seeds',[11,22,33])),'completed_runs':len(design),
            'model_version':config.get('model_version','v1'),
            'model_file':manifest.get('model_file', h.MODEL.name),
            'model_sha256':next(value for key,value in manifest['sha256'].items()
                                if key in {h.MODEL.name, 'MobileBankMarkets.nlogox'}),
            'exported_utc':dt.datetime.now(dt.timezone.utc).isoformat(),
            'points':points,'sensitivity':clean,
            'caveat':'Abstract, uncalibrated simulation. Error bars show between-seed SD, not confidence intervals. '
                     'LHS correlations are marginal, not causal or partial effects.'}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('results',type=Path); p.add_argument('--id',required=True); p.add_argument('--title',required=True)
    p.add_argument('--site',type=Path,default=h.ABM/'docs/results')
    p.add_argument('--replace',action='store_true',help='Explicitly replace an existing staged report')
    a=p.parse_args(); report=build_report(a.results,a.id,a.title)
    folder=a.site/'studies'; folder.mkdir(parents=True,exist_ok=True)
    destination=folder/(a.id+'.json')
    if destination.exists() and not a.replace: raise ValueError('Report exists; use --replace to replace it')
    destination.write_text(json.dumps(report,indent=2,allow_nan=False),encoding='utf-8')
    index=folder/'index.json'
    catalog=json.loads(index.read_text()) if index.exists() else {'studies':[]}
    entries=[e for e in catalog['studies'] if e['id']!=a.id]
    entries.append({'id':a.id,'title':a.title,'mode':report['mode'],'file':a.id+'.json'})
    catalog['studies']=entries
    index.write_text(json.dumps(catalog,indent=2),encoding='utf-8')
    print(f'Staged synthetic summary: {destination}. No commit, upload, or deployment performed.')


if __name__=='__main__':
    try: main()
    except (ValueError,OSError,KeyError) as exc:
        print('Error: '+str(exc),file=sys.stderr); sys.exit(2)
