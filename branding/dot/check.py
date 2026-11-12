"""Validate the vendored dot. data; no third-party dependencies."""
import json
import pathlib
import re
import xml.etree.ElementTree as ET

root = pathlib.Path(__file__).resolve().parent
tokens = json.loads((root / 'tokens.json').read_text())
assert tokens['schemaVersion'] == 1
assert tokens['suite'] == 'dot.'
assert re.fullmatch(r'\d+\.\d+\.\d+', tokens['version'])
for palette in tokens['colors'].values():
    for color in palette.values():
        assert re.fullmatch(r'#[0-9A-Fa-f]{6}', color), color
assert all(isinstance(v, int) and v > 0 for v in tokens['spacing'].values())
for path in (root / 'logos').glob('*.svg'):
    svg = ET.parse(path).getroot()
    assert svg.tag == '{http://www.w3.org/2000/svg}svg'
    assert not any(node.tag.endswith('script') for node in svg.iter())
for name in ['identity', 'copy', 'releases']:
    assert (root / 'guidelines' / (name + '.md')).read_text().strip()
assert (root / 'tokens.css').is_file()
assert (root / 'tokens.ts').is_file()
print('dot. brand kit valid:', tokens['version'])
