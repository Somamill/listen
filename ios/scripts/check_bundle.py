#!/usr/bin/env python3
"""Validate iOS, simulator and Mac Catalyst app packaging without signing access."""
import hashlib
import plistlib
import sys
from pathlib import Path

bundle = Path(sys.argv[1])
source = Path(__file__).resolve().parents[1] / 'Listen/Resources/Sample.mp3'
# Catalyst bundles use the macOS Contents layout, including nested extensions.
def contents(target):
    return target / 'Contents' if (target / 'Contents/Info.plist').is_file() else target
def resources(target):
    root = contents(target)
    return root / 'Resources' if root.name == 'Contents' else root
def executable(target, info):
    root = contents(target)
    return root / 'MacOS' / info['CFBundleExecutable'] if root.name == 'Contents' else root / info['CFBundleExecutable']
def require(condition, message):
    if not condition:
        raise SystemExit(message)
def digest(path):
    data = path.read_bytes()
    require(len(data) > 0, f'Empty packaged resource: {path.name}')
    return hashlib.sha256(data).digest()
require(digest(source) == digest(resources(bundle) / 'Sample.mp3'), 'Packaged sample differs from source; hydrate resources and rebuild.')
app_info = plistlib.loads((contents(bundle) / 'Info.plist').read_bytes())
for target in [bundle, contents(bundle) / 'PlugIns/ListenShare.appex', contents(bundle) / 'PlugIns/ListenWidgets.appex']:
    info = plistlib.loads((contents(target) / 'Info.plist').read_bytes())
    require(executable(target, info).stat().st_size > 0, f'Missing executable: {target.name}')
    require(info['CFBundleShortVersionString'] == app_info['CFBundleShortVersionString'], f'Version mismatch: {target.name}')
    require(info['CFBundleVersion'] == app_info['CFBundleVersion'], f'Build mismatch: {target.name}')
    require(info['CFBundleIdentifier'] == app_info['CFBundleIdentifier'] or info['CFBundleIdentifier'].startswith(app_info['CFBundleIdentifier'] + '.'), f'Identifier mismatch: {target.name}')
require((resources(bundle) / 'PrivacyInfo.xcprivacy').is_file(), 'Missing privacy manifest')

print(f'PASS: audio, app/extensions, identifiers, privacy manifest and version {app_info["CFBundleShortVersionString"]} ({app_info["CFBundleVersion"]})')
