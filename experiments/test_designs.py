import csv
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('harness', Path(__file__).with_name('run_experiments.py'))
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)


class Designs(unittest.TestCase):
    def test_oat_and_seed_pairing(self):
        cfg = {'mode':'oat','seeds':[11,22], 'parameters':{'settlement-delay':[0,1,2],
                                                        'low-balance-percent':[15,25,35]}}
        rows, rejected = h.build_design(cfg)
        self.assertFalse(rejected)
        self.assertEqual(len(rows), 10)
        baseline = rows[0]
        for row in rows[2:]:
            differences = [name for name in h.controls()[0] if name != 'model-seed' and row[name] != baseline[name]]
            self.assertEqual(differences, [row['varied_parameter']])
        self.assertEqual([r['model-seed'] for r in rows], [11,22]*5)

    def test_factorial(self):
        rows,_ = h.build_design({'mode':'grid','seeds':[11],
                                'parameters':{'settlement-delay':[0,1,2],'minimum-reserve':[0,100]}})
        self.assertEqual(len(rows),6)
        self.assertEqual(len({(r['settlement-delay'],r['minimum-reserve']) for r in rows}),6)

    def test_lhs_is_stratified_and_reproducible(self):
        cfg={'mode':'lhs','samples':12,'design_seed':7,'seeds':[11],
             'parameters':{'network-density':{'min':0,'max':1},'settlement-delay':{'values':[0,1,2]}}}
        rows,_=h.build_design(cfg)
        self.assertEqual(rows,h.build_design(cfg)[0])
        self.assertEqual(sorted(int(r['network-density']*12) for r in rows),list(range(12)))
        self.assertEqual(sorted([r['settlement-delay'] for r in rows]),[0]*4+[1]*4+[2]*4)

    def test_constraints_are_explicit(self):
        cfg={'mode':'grid','seeds':[11],
             'parameters':{'low-balance-percent':[25,45],'target-balance-percent':[40,50]}}
        with self.assertRaises(ValueError): h.build_design(cfg)
        cfg['invalid_combinations']='skip'
        rows,rejected=h.build_design(cfg)
        self.assertEqual((len(rows),len(rejected)),(3,1))
        with self.assertRaises(ValueError):
            h.build_design({'mode':'oat','base':{'network-source':'Observed mutual willingness'},
                            'parameters':{'network-density':[0.1,0.9]}})
        with self.assertRaises(ValueError):
            h.build_design({'parameters':{'typo':[0]}})

    def test_paired_effects_and_failed_runs(self):
        cfg={'mode':'oat','seeds':[11,22], 'parameters':{'settlement-delay':[0,1]}}
        design,_=h.build_design(cfg)
        rows=[]
        for i,d in enumerate(design):
            row={'run_id':d['run_id'],'status':'ok','error':''}
            row.update({m:float(i) for m in h.METRICS})
            rows.append(row)
        # Later successful checkpoint replaces a failed attempt for the same run.
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)
            h.write_csv(out/'attempts.csv',[dict(rows[0],status='error'),*rows])
            results=h.summarize(out,design,cfg)
            self.assertEqual(len(results),4)
            with (out/'oat_effects.csv').open() as f: effects=list(csv.DictReader(f))
            self.assertTrue(all(float(r['paired_difference_mean'])==2 for r in effects))

    def test_incomplete_checkpoint_is_not_successful(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'attempts.csv'
            path.write_text('run_id,status,error,service_pct\np00000-s11,ok,,50\n')
            self.assertEqual(h.read_attempts(path),{})


if __name__=='__main__': unittest.main()
