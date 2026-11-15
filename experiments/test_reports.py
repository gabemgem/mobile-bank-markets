import csv
import json
from pathlib import Path
import tempfile
import unittest
import run_experiments as h
import performance as perf
import export_report as export


class Reports(unittest.TestCase):
    def fixture(self,folder):
        config={'mode':'oat','ticks':5,'seeds':[11,22],
                'base':{'minimum-reserve':175,'target-balance-percent':60},
                'parameters':{'settlement-delay':[0,1]}}
        design,_=h.build_design(config)
        rows=[]
        for i,d in enumerate(design):
            rows.append({'run_id':d['run_id'],'status':'ok','error':'',
                         'active_market':'','network_type':'Synthetic: undirected Erdos-Renyi',
                         **{m:float(i) for m in h.METRICS}})
        h.write_csv(folder/'design.csv',design);h.write_csv(folder/'attempts.csv',rows)
        (folder/'config.json').write_text(json.dumps(config))
        (folder/'manifest.json').write_text(json.dumps({'sha256':{'MobileBankMarkets.nlogox':'test'}}))
        h.summarize(folder,design,config)

    def test_public_export_and_privacy_rejection(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);self.fixture(folder)
            report=export.build_report(folder,'oat','Test')
            self.assertEqual((len(report['points']),report['replicates']),(2,2))
            self.assertNotIn('selected-market',report['points'][0]['parameters'])
            self.assertNotIn('model-seed',report['points'][0]['parameters'])
            self.assertEqual(report['seeds'],[11,22])
            baseline=next(p for p in report['points'] if p['varied']=='baseline')
            self.assertEqual(baseline['parameters']['minimum-reserve'],175)
            self.assertEqual(baseline['parameters']['target-balance-percent'],60)
            (folder/'manifest.json').write_text(json.dumps({'sha256':{'data/nodes.csv':'private'}}))
            with self.assertRaises(ValueError):export.build_report(folder,'oat','Test')

    def test_public_export_requires_complete_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);self.fixture(folder)
            with (folder/'attempts.csv').open(newline='',encoding='utf-8') as f:
                rows=list(csv.DictReader(f))
            h.write_csv(folder/'attempts.csv',rows[:-1])
            with self.assertRaises(ValueError):export.build_report(folder,'oat','Test')

    def test_benchmark_is_small_and_replicated(self):
        design=perf.benchmark_design([50,500],2)
        self.assertEqual(len(design),24)
        self.assertTrue(all(r['network-source']=='Synthetic random' for r in design))
        self.assertEqual(len({r['run_id'] for r in design}),24)

    def test_prepared_counts_and_seeds(self):
        for name in ['oat','lhs','grid']:
            cfg=json.loads((h.ABM/f'experiments/configs/{name}.json').read_text())
            rows,_=h.build_design(cfg)
            self.assertGreater(len(rows),0)
            for point in {r['point_id'] for r in rows}:
                self.assertEqual({r['model-seed'] for r in rows if r['point_id']==point},set(cfg['seeds']))
            self.assertTrue(all(r['network-source']=='Synthetic random' for r in rows))

    def test_runtime_estimate_rejects_changed_model(self):
        rows,_=h.build_design({'mode':'grid','seeds':[11],
                             'parameters':{'settlement-delay':[1]}})
        profile={'version':1,'model_sha256':'wrong','runner_sha256':'wrong'}
        with self.assertRaises(ValueError):perf.estimate(profile,rows,{})


if __name__=='__main__':unittest.main()
