import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import policy_study as study
import run_experiments as h


class PolicyStudy(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec, cls.catalog, cls.identity = study.load(study.DEFAULT)

    def tearDown(self):
        h.select_model('v1')

    def test_core_count_pairing_and_demand(self):
        spec = self.spec
        total = len(spec['generators'])*len(spec['sizes'])*spec['graphs_per_size']*len(spec['policies'])*len(spec['seeds'])
        self.assertEqual(total, 147200)
        graphs = study.graphs(spec, self.catalog, 'pooled', 12)
        rows = study.batch_design(spec, graphs)
        self.assertEqual(len(rows), 3200)
        self.assertEqual(len({r['run_id'] for r in rows}), 3200)
        self.assertTrue(all(r['requests-per-tick'] == 24 for r in rows))
        policies = {}
        for row in rows:
            policies.setdefault((row['selected-market'], row['model-seed']), set()).add(row['policy_id'])
        self.assertEqual(len(policies), 400)
        self.assertTrue(all(len(p) == 8 for p in policies.values()))

    def test_benchmark_covers_size_policy_density_and_horizon(self):
        rows = study.benchmark_design(self.spec, self.catalog)
        self.assertEqual(len(rows), 576)
        self.assertEqual(len({r['run_id'] for r in rows}), 576)
        self.assertEqual(rows, study.benchmark_design(self.spec, self.catalog))
        self.assertEqual({r['ticks'] for r in rows}, {200, 1000, 3000})
        self.assertEqual({r['benchmark_role'] for r in rows}, {'sparse', 'dense'})
        self.assertEqual({r['generator'] for r in rows}, {'pooled', 'corrected_hub'})

    def test_invalid_policy_settings_and_checkpoints_fail(self):
        spec = copy.deepcopy(self.spec)
        spec['policies'][0]['sharing-mode'] = 'invalid'
        selected = study.graphs(spec, self.catalog, 'pooled', 2)
        with self.assertRaises(ValueError):
            study.batch_design(spec, selected)
        for checkpoints in [[0], [5, 5], [5, 3], [1001], '100']:
            with self.assertRaises(ValueError):
                h.build_design({'model_version':'v2', 'ticks':1000, 'checkpoints':checkpoints,
                                'parameters':{'grid-cell-size':[5]}})

    def test_cost_estimate_includes_batch_overhead_and_allowance(self):
        spec = copy.deepcopy(self.spec)
        spec.update(sizes=[2], generators=['pooled'], graphs_per_size=2, seeds=[11, 22])
        spec['policies'] = spec['policies'][:2]
        selected = study.graphs(spec, self.catalog, 'pooled', 2)
        design = study.batch_design(spec, selected)
        for row in design:
            row['benchmark_role'] = 'sparse' if row['point_id'].endswith('g00') else 'dense'
        attempts = {r['run_id']: {'status':'ok', 'seconds':'4'} for r in design}
        plan = {'planned_runs':8, 'batches':[{'generator':'pooled', 'size':2, 'runs':8}]}
        spec['benchmark']['sizes'] = [2]
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            (folder/'manifest.json').write_text(json.dumps({'config':{'study_identity':self.identity}}))
            (folder/'timing.json').write_text(json.dumps({'compile_seconds':2, 'engine_wall_seconds':40}))
            with patch.object(study, 'benchmark_design', return_value=design), \
                    patch.object(h, 'read_attempts', return_value=attempts), \
                    patch.object(study, 'check_measurements', return_value=32):
                result = study.estimate(spec, self.catalog, self.identity, folder, plan)
            self.assertEqual(result['estimated_seconds'], 42)
            self.assertEqual(result['planning_seconds'], 58)


if __name__ == '__main__':
    unittest.main()
