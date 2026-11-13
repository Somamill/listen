#!/usr/bin/env python3
"""Package committed mobile source and an arm64 Simulator app; never creates an IPA."""
import hashlib
import plistlib
import subprocess
import sys
import zipfile
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
app = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
output.mkdir(parents=True, exist_ok=True)
subprocess.run([sys.executable, str(repo / 'ios/scripts/check_bundle.py'), str(app)], check=True)
info = plistlib.loads((app / 'Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
files = subprocess.check_output(['/usr/bin/git', 'ls-files', '-z', 'ios', 'branding/dot', 'LICENSE', '.github/workflows/ios.yml'], cwd=repo).decode().strip('\0').split('\0')
source = output / f'listen-ios-{version}-source.zip'
with zipfile.ZipFile(source, 'w', zipfile.ZIP_DEFLATED) as archive:
    for name in files:
        archive.write(repo / name, 'listen-ios/' + name)
simulator = output / f'listen-ios-{version}-simulator.zip'
with zipfile.ZipFile(simulator, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob('*')):
        relative = path.relative_to(app)
        if path.is_file() and not any(part.endswith('.xctest') for part in relative.parts):
            archive.write(path, 'Listen.app/' + relative.as_posix())
for path in [source, simulator]:
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise SystemExit('Archive integrity failed: ' + path.name)
notes = f'''listen. mobile {version} — developer preview

Source: {source.name}
Open listen-ios/ios/Listen.xcodeproj with Xcode. Setup, capability requirements,
REA comparison and validation are in listen-ios/ios/README.md and ios/docs/.

Simulator: {simulator.name}
For an Apple Silicon Mac with a compatible iOS Simulator runtime only.
Unzip, start one iPhone/iPad Simulator, then run:
  xcrun simctl install booted Listen.app
  xcrun simctl launch booted {info['CFBundleIdentifier']}

This is not an IPA and cannot be installed directly on a real iPhone or iPad.
Real devices require your signing team and provisioned App Group/iCloud/Keychain
capabilities. The unsigned simulator cannot store server tokens in Keychain.
Live Goodreads/server accounts, two-device iCloud, widgets/share/Siri on hardware,
and CarPlay remain unverified. CarPlay is disabled until its approved entitlement
is configured. Apple Watch and full BookPlayer parity are not included.

No torrent code or personal Mac configuration is included in the mobile preview.
All bundled audio is a generated test tone. Original audio files are preserved.
'''
(output / 'START-HERE.txt').write_text(notes)
(output / 'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n' for p in [source, simulator]))
for path in [source, simulator]:
    print(path.name, path.stat().st_size, 'bytes; ZIP integrity PASS')
