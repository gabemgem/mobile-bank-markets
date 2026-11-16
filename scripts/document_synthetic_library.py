"""Describe the anonymous import library without exporting estimation artifacts."""
import argparse
import csv
import hashlib
import json
from collections import Counter
from pathlib import Path


def canonical_hash(path):
    return hashlib.sha256(path.read_bytes().replace(b'\r\n', b'\n')).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library', type=Path, default=Path('synthetic-networks'))
    args = parser.parse_args()
    folder = args.library
    with (folder / 'networks.csv').open(newline='', encoding='utf-8') as stream:
        rows = list(csv.DictReader(stream))
    counts = Counter((row['generator'], int(row['n_nodes'])) for row in rows)
    assert rows and len({row['network_id'] for row in rows}) == len(rows)
    assert len(set(counts.values())) == 1, 'Unbalanced generator/size cells'
    sizes = sorted({int(row['n_nodes']) for row in rows})
    fits = sorted({row['fit_id'] for row in rows})
    sources = [Path(p) for p in ['experiments/configs/generate_abm_networks.R',
        'scripts/generate_abm_networks.R', 'scripts/abm_network_generation_functions.R',
        'scripts/pooled_mutual_ergm_functions.R', 'scripts/shrinkage_mutual_ergm_functions.R',
        'scripts/activity_ergm_functions.R', 'scripts/forecast_activity_functions.R',
        'scripts/nested_network_functions.R']]
    manifest = {
        'format_version': 1, 'relationship': 'undirected mutual stated willingness to trade',
        'primary_generator': 'pooled', 'sensitivity_generator': 'corrected_hub',
        'network_count': len(rows), 'sizes': sizes, 'networks_per_size_per_generator': next(iter(counts.values())),
        'parameter_fits': fits, 'parameter_sampling': 'equal-weight whole-market bootstrap refits',
        'all_market_point_fit_in_ensemble': False,
        'sha256_convention': 'UTF-8 file bytes with CRLF normalized to LF',
        'files_sha256_lf': {name: canonical_hash(folder / name) for name in ['networks.csv', 'nodes.csv', 'edges.csv']},
        'source_sha256_lf': {p.as_posix(): canonical_hash(p) for p in sources},
    }
    (folder / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8', newline='\n')
    text = f'''# Synthetic market networks

This library contains {len(rows)} newly generated undirected mutual stated
willingness-to-trade graphs: {next(iter(counts.values()))} replicates per generator
at every kiosk count from {min(sizes)} to {max(sizes)}.

- **pooled**: primary pooled degree-plus-closure ERGM.
- **corrected_hub**: latent-activity, corrected-density/closure sensitivity alternative.

Each generator uses {len(fits)} equally weighted whole-market bootstrap refits.
The all-market point fit is a separate reference, not an extra ensemble member.
Graph seeds and parameter-fit labels are recorded in networks.csv. Financial
behavior and simulation seeds remain separate NetLogo settings.

Keep networks.csv, nodes.csv, and edges.csv together. All nodes, including
isolates, are supplied; each undirected edge appears once. Repeated graph shapes,
empty graphs, and complete graphs are retained as valid random outcomes.

In desktop NetLogo 7.0.3, open ../MobileBankMarkets.nlogox, choose **Imported
synthetic**, then use **Choose local network** to select generator, size, and ID.
Reopen the chooser after replacing files to refresh the in-memory cache.
In NetLogo Web, click **Load GitHub library**, wait for **Ready: 920 GitHub
graphs**, enter an ID such as `pooled-n20-r01` or `corrected-hub-n20-r01`,
and click **Setup**. The default URL downloads this published library directly.
For desktop/headless use, first run `python scripts/install_netlogo_fetch.py`
from the repository directory to install the official Fetch extension.

All node and graph IDs are synthetic. No respondent IDs, observed adjacencies,
or fit objects are included. Generation from fitted survey structure is not a
formal privacy guarantee; review this library before public release. Private
fits and source-market resamples stay under ignored local directories.

The manifest records canonical-LF checksums so verification survives Git line-ending
conversion. Reproducing a graph also requires its private fitted parameter tuple.
See [generation instructions](../experiments/GENERATE_ABM_NETWORKS.md) and the
[site explanation](../docs/synthetic-networks/index.md).
'''
    (folder / 'README.md').write_text(text, encoding='utf-8', newline='\n')
    print(f'Documented {len(rows)} networks and canonical file checksums in {folder}.')


if __name__ == '__main__':
    main()
