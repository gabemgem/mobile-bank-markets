"""Small synthetic benchmark and workload-specific runtime estimates."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import statistics as stats
import sys
import run_experiments as h

CASES = [
    ('dense-network',40,.8,80,'Network sharing',2),
    ('baseline-network',20,.3,40,'Network sharing',1),
    ('sparse-no-sharing',10,.1,20,'No sharing',1),
    ('instant-all-to-all',20,.3,40,'All-to-all sharing',0),
    ('dense-all-to-all',40,.8,80,'All-to-all sharing',2),
    ('instant-network',20,.8,40,'Network sharing',0),
]


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def benchmark_design(lengths, repeats):
    rows=[]
    for label,n,density,demand,policy,delay in CASES:
        for ticks in lengths:
            cfg={'mode':'grid','ticks':ticks,'seeds':[11*(i+1) for i in range(repeats)],
                 'base':{'network-source':'Synthetic random','number-of-kiosks':n,
                         'network-density':density,'requests-per-tick':demand,'sharing-mode':policy},
                 'parameters':{'settlement-delay':[delay]}}
            part,_=h.build_design(cfg)
            point=f'p{len(rows)//repeats:05d}'
            for row in part:
                row.update(run_id=f'{point}-s{row["model-seed"]}',point_id=point,
                           benchmark_case=label,mode='benchmark')
                rows.append(row)
    return rows


def make_profile(out,design):
    runs=h.read_attempts(out/'attempts.csv')
    if len(runs)!=len(design) or any(r['status']!='ok' for r in runs.values()):
        raise ValueError('Benchmark incomplete or failed; inspect results before estimating')
    timing=json.loads((out/'timing.json').read_text())
    engine=json.loads((out/'engine_timing.json').read_text())
    cases=[]
    for label,*_ in CASES:
        sample=[d|runs[d['run_id']] for d in design if d['benchmark_case']==label]
        horizons=sorted({int(r['ticks']) for r in sample})
        by_ticks={t:stats.median(float(r['simulation_seconds']) for r in sample if int(r['ticks'])==t) for t in horizons}
        slope=(by_ticks[horizons[-1]]-by_ticks[horizons[0]])/(horizons[-1]-horizons[0])
        rates=[float(r['simulation_seconds'])/int(r['ticks']) for r in sample]
        slope=max(slope,stats.median(rates)*.5)  # Avoid negative/near-zero estimates from timer noise.
        first=sample[0]
        cases.append({'case':label,'number-of-kiosks':int(first['number-of-kiosks']),
            'network-density':float(first['network-density']),'requests-per-tick':int(first['requests-per-tick']),
            'sharing-mode':first['sharing-mode'],'settlement-delay':int(first['settlement-delay']),
            'setup_seconds':stats.median(float(r['setup_seconds']) for r in sample),
            'metrics_seconds':stats.median(float(r['metrics_seconds']) for r in sample),
            'seconds_per_tick':slope,'planning_seconds_per_tick':max(rates),
            'measured_ticks':horizons,'measured_replicates':len(sample),
            'median_run_seconds':stats.median(float(r['seconds']) for r in sample)})
    measured=sum(float(r['seconds']) for r in runs.values())
    overhead=timing['compile_seconds']+max(0,timing['engine_wall_seconds']-measured-engine['warmup_seconds'])
    return {'version':1,'kind':'performance-benchmark','network_source':'Synthetic random',
            'model_sha256':sha(h.MODEL),'runner_sha256':sha(h.ABM/'experiments/BatchRunner.java'),
            'environment':{'os':platform.system(),'logical_cpus':os.cpu_count(),'python':platform.python_version()},
            'measured_runs':len(design),'warmup_runs':engine['warmup_runs'],
            'measured_wall_seconds':timing['compile_seconds']+timing['engine_wall_seconds'],
            'startup_seconds':overhead,'cases':cases,
            'caveat':'Machine-specific planning estimates, not confidence intervals. '
                     'Long horizons are extrapolated; matching activity and background load can change runtime.'}


def estimate(profile,design,config):
    if profile.get('version')!=1 or profile.get('model_sha256')!=sha(h.MODEL) or profile.get('runner_sha256')!=sha(h.ABM/'experiments/BatchRunner.java'):
        raise ValueError('Performance profile does not match the current model/runner; benchmark again')
    if any(r['network-source']!='Synthetic random' for r in design):
        raise ValueError('This performance profile covers abstract Synthetic random networks only')
    total=profile['startup_seconds']; budget=profile['startup_seconds']; warnings=set(); first_cost=None
    for row in design:
        candidates=[c for c in profile['cases'] if c['sharing-mode']==row['sharing-mode']]
        if not candidates: raise ValueError('Policy is outside the benchmark profile')
        def distance(c):
            return (math.log(max(row['number-of-kiosks'],1)/c['number-of-kiosks'])**2
                    +math.log(max(row['requests-per-tick'],1)/c['requests-per-tick'])**2
                    +(row['network-density']-c['network-density'])**2
                    +.05*abs(row['settlement-delay']-c['settlement-delay']))
        case=min(candidates,key=distance)
        scale=max(row['number-of-kiosks']/case['number-of-kiosks'],
                  row['requests-per-tick']/case['requests-per-tick'],1)
        cost=case['setup_seconds']+case['metrics_seconds']+case['seconds_per_tick']*row['ticks']*scale
        conservative=case['setup_seconds']+case['metrics_seconds']+case['planning_seconds_per_tick']*row['ticks']*scale
        if first_cost is None: first_cost=cost
        total+=cost; budget+=max(1.5*cost,conservative)
        if row['ticks']>max(case['measured_ticks']): warnings.add('Horizon exceeds measured range; per-tick cost is extrapolated.')
        if scale>1: warnings.add('Some workloads exceed their nearest benchmark case; upward workload scaling was applied.')
    warmup=config.get('warmup_runs',0)*(first_cost or 0)
    return {'planned_runs':len(design),'warmup_runs':config.get('warmup_runs',0),
            'estimated_seconds':total+warmup,'planning_seconds':budget+1.5*warmup,
            'warnings':sorted(warnings),'method':'Nearest policy/workload case; setup plus measured tick rate. '
            'Planning allowance uses at least 1.5x run costs, not a statistical confidence bound.'}


def format_estimate(e):
    def duration(s): return f'{s:.0f} s ({s/60:.1f} min)'
    return (f"{e['planned_runs']} runs + {e['warmup_runs']} warm-ups: estimated {duration(e['estimated_seconds'])}; "
            f"planning allowance {duration(e['planning_seconds'])}.\n"+'\n'.join(e['warnings']))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=h.ABM/'results/performance')
    parser.add_argument('--ticks',type=int,nargs=2,default=[50,500])
    parser.add_argument('--repeats',type=int,default=2)
    parser.add_argument('--netlogo-home',type=Path,default=Path('C:/Program Files/NetLogo 7.0.3'))
    parser.add_argument('--java'); parser.add_argument('--javac')
    parser.add_argument('--dry-run',action='store_true'); parser.add_argument('--resume',action='store_true')
    parser.add_argument('--public-report',type=Path,help='Optional sanitized synthetic timing report for the static dashboard')
    args=parser.parse_args()
    if not 1<=args.repeats<=5 or not 1<=min(args.ticks)<max(args.ticks)<=1000:
        raise ValueError('Use two distinct horizons between 1 and 1000 and 1--5 repetitions')
    args.ticks=sorted(args.ticks)
    design=benchmark_design(args.ticks,args.repeats)
    config={'mode':'benchmark','ticks_by_case':args.ticks,'repeats':args.repeats,
            'seeds':[11*(i+1) for i in range(args.repeats)],'warmup_runs':2,'parameters':{},'cases':CASES}
    if h.execute_design(config,design,[],args): return 1
    if args.dry_run: return 0
    profile=make_profile(args.out.resolve(),design)
    for title,path in [('oat',h.ABM/'experiments/configs/oat.json'),
                       ('lhs',h.ABM/'experiments/configs/lhs.json'),('grid',h.ABM/'experiments/configs/grid.json')]:
        cfg=json.loads(path.read_text()); rows,_=h.build_design(cfg)
        profile.setdefault('estimates',{})[title]=estimate(profile,rows,cfg)
        print(title.upper()+': '+format_estimate(profile['estimates'][title]),flush=True)
    (args.out/'profile.json').write_text(json.dumps(profile,indent=2),encoding='utf-8')
    if args.public_report:
        args.public_report.parent.mkdir(parents=True,exist_ok=True)
        args.public_report.write_text(json.dumps(profile,indent=2),encoding='utf-8')
    return 0


if __name__=='__main__':
    try: sys.exit(main())
    except (ValueError,OSError) as exc:
        print('Error: '+str(exc),file=sys.stderr); sys.exit(2)
