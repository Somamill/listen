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

def luminance(hex_color):
    channels = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    linear = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in channels]
    return sum(v * weight for v, weight in zip(linear, (.2126, .7152, .0722)))

def contrast(first, second):
    high, low = sorted((luminance(first), luminance(second)), reverse=True)
    return (high + .05) / (low + .05)

# Protect the actual body, muted, link and primary-action roles in both themes.
pressed_opacity = tokens['interaction']['pressedOpacity']
assert .9 <= pressed_opacity <= 1

def composite(foreground, background):
    return '#' + ''.join(f'{round(int(foreground[i:i + 2], 16) * pressed_opacity + int(background[i:i + 2], 16) * (1 - pressed_opacity)):02x}' for i in (1, 3, 5))

for theme in ('light', 'dark'):
    palette = tokens['colors'][theme]
    for foreground in ('text', 'secondaryText'):
        for background in ('background', 'surface'):
            assert contrast(palette[foreground], palette[background]) >= 4.5, (theme, foreground, background)
    for app, accent in tokens['colors']['accents' if theme == 'light' else 'accentsDark'].items():
        assert contrast(accent, tokens['colors']['onAccent'][theme]) >= 4.5, (theme, app, 'button')
        assert contrast(accent, palette['background']) >= 4.5, (theme, app, 'link')
        for canvas in ('background', 'surface'):
            background = palette[canvas]
            assert contrast(composite(accent, background), background) >= 4.5, (theme, app, 'pressed link')
            assert contrast(composite(tokens['colors']['onAccent'][theme], background), composite(accent, background)) >= 4.5, (theme, app, 'pressed button')
for path in (root / 'logos').glob('*.svg'):
    svg = ET.parse(path).getroot()
    assert svg.tag == '{http://www.w3.org/2000/svg}svg'
    assert not any(node.tag.endswith('script') for node in svg.iter())
for name in ['identity', 'copy', 'releases']:
    assert (root / 'guidelines' / (name + '.md')).read_text().strip()
assert (root / 'tokens.css').is_file()
assert (root / 'tokens.ts').is_file()
print('dot. brand kit valid:', tokens['version'])
