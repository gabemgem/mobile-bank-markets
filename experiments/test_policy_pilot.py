import itertools
import json
from pathlib import Path
import tempfile
import unittest

import policy_pilot_report as report
import run_experiments as h


class PolicyPilot(unittest.TestCase):
    def tearDown(self):
        h.select_model('v1')

    def fixture(self):
        h.select_model('v2')
        rows = []
        for seed, sharing, external, subsidy in itertools.product(
                [11, 22], ['No sharing', 'Network sharing'],
                ['Disabled', 'External only', 'Peers then external'], [0, 50, 100]):
            peer = sharing == 'Network sharing' and external != 'External only'
            rows.append({**dict.fromkeys(h.METRICS, '0'),
                         'selected-market': 'pooled-n08-r01', 'model-seed': str(seed),
                         'sharing-mode': sharing, 'external-mode': external,
                         'commission-subsidy-percent': str(subsidy),
                         'service_pct': str(10 + (10 + subsidy / 100 if peer else 0)),
                         'requested_count': '100', 'deposit_requested_value': '500',
                         'withdrawal_requested_value': '500'})
        return rows

    def test_paired_effects_and_inactive_policy_checks(self):
        rows = self.fixture()
        summary, checks = report.compare(rows)
        self.assertEqual(checks, 20)
        result = next(r for r in summary if r['network'] == 'All' and r['policy'] == 'Network + 100% subsidy')
        self.assertEqual(result['service_change_pp_mean'], 11)
        self.assertEqual(result['paired_runs'], 2)
        rows[1]['service_pct'] = '99'
        with self.assertRaisesRegex(ValueError, 'Inactive subsidy'):
            report.compare(rows)

    def test_runtime_scaling_keeps_fixed_costs(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            (folder / 'timing.json').write_text(json.dumps({'compile_seconds': 1, 'engine_wall_seconds': 40}))
            (folder / 'engine_timing.json').write_text(json.dumps({'warmup_seconds': 2}))
            rows = [{'setup_seconds': 1, 'metrics_seconds': 1, 'simulation_seconds': t,
                     'seconds': t + 2} for t in [8, 16]]
            result = report.estimate(folder, {'ticks': 200}, rows, 2, 1000)
            self.assertAlmostEqual(result['estimated_seconds'], 145)
            self.assertAlmostEqual(result['planning_seconds'], 207)
            self.assertTrue(result['extrapolated_horizon'])


if __name__ == '__main__':
    unittest.main()
