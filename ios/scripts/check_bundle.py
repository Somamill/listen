#!/usr/bin/env python3
"""Validate preview packaging before distributing a simulator or device build."""
import hashlib
import plistlib
import sys
from pathlib import Path

bundle = Path(sys.argv[1])
source = Path(__file__).resolve().parents[1] / 'Listen/Resources/Sample.mp3'
def require(condition, message):
    if not condition:
        raise SystemExit(message)
def digest(path):
    data = path.read_bytes()
    require(len(data) > 0, f'Empty packaged resource: {path.name}')
    return hashlib.sha256(data).digest()
require(digest(source) == digest(bundle / 'Sample.mp3'), 'Packaged sample differs from source; hydrate resources and rebuild.')
app_info = plistlib.loads((bundle / 'Info.plist').read_bytes())
for target in [bundle, bundle / 'PlugIns/ListenShare.appex', bundle / 'PlugIns/ListenWidgets.appex']:
    info = plistlib.loads((target / 'Info.plist').read_bytes())
    require((target / info['CFBundleExecutable']).stat().st_size > 0, f'Missing executable: {target.name}')
    require(info['CFBundleShortVersionString'] == app_info['CFBundleShortVersionString'], f'Version mismatch: {target.name}')
    require(info['CFBundleIdentifier'].startswith(app_info['CFBundleIdentifier']), f'Identifier mismatch: {target.name}')
print(f'PASS: sample checksum, app/extensions, identifiers and version {app_info["CFBundleShortVersionString"]}')
