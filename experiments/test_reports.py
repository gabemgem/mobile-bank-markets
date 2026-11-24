import csv
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
import run_experiments as h
import performance as perf
import export_report as export


class Reports(unittest.TestCase):
    def setUp(self): h.select_model('v1')

    def test_github_dropdown_matches_public_catalog(self):
        h.select_model('v2')
        widget = ET.parse(h.MODEL).find("widgets/chooser[@variable='ui-github-network-id']")
        self.assertIsNotNone(widget)
        with (h.ABM/'synthetic-networks/networks.csv').open(newline='', encoding='utf-8') as source:
            ids = {row['network_id'] for row in csv.DictReader(source)}
        choices = [choice.get('value') for choice in widget]
        self.assertEqual(set(choices), ids)
        self.assertEqual(len(choices), len(ids))
        self.assertEqual(widget[int(widget.get('current'))].get('value'), 'pooled-n20-r01')
        self.assertEqual(widget.get('display'), widget.get('variable'))
        self.assertNotIn('github-network-id', h.controls()[0])
        h.select_model('v1')

    def fixture(self,folder,version='v1'):
        config={'model_version':version,'mode':'oat','ticks':5,'seeds':[11,22],
                'base':{'minimum-reserve':175,'target-balance-percent':60},
                'parameters':{'grid-cell-size':[2,5]} if version=='v2' else {'settlement-delay':[0,1]}}
        design,_=h.build_design(config)
        rows=[]
        for i,d in enumerate(design):
            rows.append({'run_id':d['run_id'],'status':'ok','error':'',
                         'active_market':'','network_type':'Synthetic: undirected Erdos-Renyi',
                         **{m:float(i) for m in h.METRICS}})
        h.write_csv(folder/'design.csv',design);h.write_csv(folder/'attempts.csv',rows)
        (folder/'config.json').write_text(json.dumps(config))
        (folder/'manifest.json').write_text(json.dumps({'sha256':{h.MODEL.name:'test'}}))
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

    def test_export_keeps_version_and_historical_hash_compatibility(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);self.fixture(folder,'v2')
            report=export.build_report(folder,'v2-test','V2 test')
            self.assertEqual(report['model_version'],'v2')
            self.assertEqual(report['model_file'],'MobileBankMarkets_v2.nlogox')
            self.assertIn('closure_failed_count',report['points'][0]['metrics'])
            self.fixture(folder,'v1')
            (folder/'manifest.json').write_text(json.dumps({'sha256':{'MobileBankMarkets.nlogox':'historical'}}))
            self.assertEqual(export.build_report(folder,'legacy','Legacy')['model_sha256'],'historical')
        h.select_model('v1')

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

    def test_v2_prepared_designs(self):
        for name,count in [('smoke',12),('oat',100),('grid',90),('lhs',120),('commission-grid',90),('spatial-smoke',16),('policy-pilot',324),('policy-timing',72)]:
            cfg=json.loads((h.ABM/f'experiments/configs/v2-{name}.json').read_text())
            rows,rejected=h.build_design(cfg)
            self.assertEqual(len(rows),count)
            self.assertFalse(rejected)
            self.assertEqual(h.MODEL.name,'MobileBankMarkets_v2.nlogox')
        h.select_model('v1')

    def test_runtime_estimate_rejects_changed_model(self):
        rows,_=h.build_design({'mode':'grid','seeds':[11],
                             'parameters':{'settlement-delay':[1]}})
        profile={'version':1,'model_sha256':'wrong','runner_sha256':'wrong'}
        with self.assertRaises(ValueError):perf.estimate(profile,rows,{})


if __name__=='__main__':unittest.main()
