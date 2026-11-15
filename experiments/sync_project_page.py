"""Keep the Pages landing page generated from the project README, not a replacement."""
from pathlib import Path
import re

base=Path(__file__).resolve().parents[1]
readme=(base/'README.md').read_text(encoding='utf-8')
def link(match):
    label,target=match.groups()
    if target.startswith(('https://','http://','#')): return match.group(0)
    if target.startswith('docs/results'):
        return f'[{label}]({target.removeprefix("docs/")})'
    local=(base/target).is_dir()
    return f'[{label}](https://github.com/gabemgem/mobile-bank-markets/{"tree" if local else "blob"}/main/{target})'
readme=re.sub(r'\[([^\]]+)\]\(([^)]+)\)',link,readme)
(base/'docs').mkdir(exist_ok=True)
(base/'docs/index.md').write_text('---\nlayout: default\ntitle: Mobile Bank Markets\n---\n\n<!-- Generated from README.md by experiments/sync_project_page.py -->\n\n'+readme,encoding='utf-8')
print('Updated docs/index.md from README.md; the README remains the project overview source.')
