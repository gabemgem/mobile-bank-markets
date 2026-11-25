import unittest

import analyze_policy_study as a


class PolicyAnalysis(unittest.TestCase):
    def test_interval_rates_use_differences_of_counts_and_values(self):
        before = dict.fromkeys(a.COUNTERS,0.0) | {'closed_share':.2}
        after = dict.fromkeys(a.COUNTERS,0.0) | {'closed_share':.3,'pending_trades':0,'external_pending':0}
        before.update(requested_count=10,served_count=8,deposit_requested_value=10,deposit_served_value=8,subsidy_spent=4)
        after.update(requested_count=100,served_count=20,deposit_requested_value=100,deposit_served_value=20,subsidy_spent=10)
        result = a.outcome(after,2,200,before,100)
        self.assertAlmostEqual(result['service_pct'],100*12/90)
        self.assertAlmostEqual(result['closed_pct'],40)
        self.assertAlmostEqual(result['subsidy_per_kiosk'],3)
        self.assertIsNone(result['withdrawal_service_pct'])

    def test_spread_and_harm_are_across_graph_means(self):
        rows = [{'family':'x','service_pct':30,'gain_pp':-2}, {'family':'x','service_pct':34,'gain_pp':2}]
        result = a.aggregate(rows,['family'],['service_pct','gain_pp'])[0]
        self.assertEqual(result['graphs'],2)
        self.assertEqual(result['gain_pp'],0)
        self.assertEqual(result['harm_pct'],50)
        self.assertAlmostEqual(result['gain_pp_q10'],-1.6)
        self.assertAlmostEqual(result['gain_pp_q90'],1.6)

    def test_ledgers_reject_unaccounted_cash(self):
        row = dict.fromkeys(a.FIELDS,0.0)
        row.update(n_kiosks=2,requested_count=10,served_count=8,deposit_requested_value=100,
                   withdrawal_requested_value=100,deposit_served_value=70,withdrawal_served_value=10,
                   service_pct=40,closure_failed_count=1,cash_failed_count=1,commissions_earned=12,
                   commissions_paid=2,subsidy_spent=10,final_cash=1070,final_efloat=940)
        a.validate_snapshot(row,2,100,500)
        row['final_cash'] += 1
        with self.assertRaisesRegex(ValueError,'Cash ledger'):
            a.validate_snapshot(row,2,100,500)

    def test_zero_cost_is_not_an_infinite_return(self):
        rows = [{'contrast':'x','gain_pp':1,'delta_value':100,'delta_subsidy':0}]
        result = a.aggregate(rows,['contrast'],['gain_pp','delta_value','delta_subsidy'])[0]
        self.assertIsNone(result['additional_value_per_subsidy_unit'])


if __name__ == '__main__':
    unittest.main()
