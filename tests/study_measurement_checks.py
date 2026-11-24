"""Headless regression check: intermediate observations must not change policy outcomes."""
import argparse
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'experiments'))
import policy_study as study
import run_experiments as h


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--java')
    parser.add_argument('--javac')
    parser.add_argument('--netlogo-home', type=Path, default=Path('C:/Program Files/NetLogo 7.0.3'))
    args = parser.parse_args()
    spec, catalog, identity = study.load(study.DEFAULT)
    spec['policies'] = spec['policies'][-2:]
    spec['seeds'] = [11, 22]
    spec['checkpoints'] = [5, 12, 24]
    selected = study.graphs(spec, catalog, 'pooled', 12)[:1]
    design = study.batch_design(spec, selected, 24)
    outputs = []
    for name, checkpoints in [('plain', []), ('checkpoints', [5, 12, 24])]:
        config = study.executor_config(spec, identity, 24)
        config['checkpoints'] = checkpoints
        run_args = argparse.Namespace(out=args.out/name, resume=False, dry_run=False,
                                     java=args.java, javac=args.javac, netlogo_home=args.netlogo_home)
        if h.execute_design(config, design, [], run_args):
            raise AssertionError('Measurement fixture did not complete')
        outputs.append(h.read_attempts(run_args.out/'attempts.csv'))
    for run in outputs[0]:
        for metric in h.METRICS:
            if outputs[0][run][metric] != outputs[1][run][metric]:
                raise AssertionError(f'Checkpoint changed {run}: {metric}')
    sample = [row | outputs[1][row['run_id']] for row in design]
    if study.check_measurements(run_args.out, sample, checkpoints) != 12:
        raise AssertionError('Missing intermediate snapshots')
    print('PASS: checkpoint observations preserve every final metric; 12 snapshots verified.')


if __name__ == '__main__':
    main()
