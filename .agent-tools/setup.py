"""Install the user-selected global agent tools. Python 3 and Node 22+."""
import argparse
import io
import json
import os
import pathlib
import shutil
import subprocess
import tarfile
import urllib.request

root = pathlib.Path(__file__).resolve().parent
config = json.loads((root / 'tools.json').read_text())
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--browser', action='store_true', help='Also install Chrome for Hallmark rendered checks')
args = parser.parse_args()
if not shutil.which('node') or not shutil.which('npm'):
    raise SystemExit('Install Node.js 22+ first.')
if int(subprocess.check_output(['node', '--version'], text=True).strip().lstrip('v').split('.')[0]) < 22:
    raise SystemExit('Node.js 22+ is required.')
subprocess.run(['npm', 'install', '--global', *[f'{name}@{version}' for name, version in config['npm'].items()]], check=True)
subprocess.run(['impeccable', 'install', '--providers=codex', '--scope=global', '--no-hooks', '--yes'], check=True)
dest = pathlib.Path.home() / '.agents' / 'skills'
dest.mkdir(parents=True, exist_ok=True)
for source in config['skills']:
    missing = [path for path in source['paths'] if not (dest / pathlib.PurePosixPath(path).name / 'SKILL.md').is_file()]
    if not missing:
        print('Skills already available:', source['repository'])
        continue
    url = f"https://codeload.github.com/{source['repository']}/tar.gz/{source['ref']}"
    with urllib.request.urlopen(url, timeout=180) as response:
        archive = tarfile.open(fileobj=io.BytesIO(response.read()), mode='r:gz')
    members = archive.getmembers()
    prefix = members[0].name.split('/')[0] + '/'
    for path in missing:
        target = dest / pathlib.PurePosixPath(path).name
        if target.exists():
            raise SystemExit(f'Existing incomplete skill preserved: {target}; inspect it before reinstalling.')
        staged = dest / ('.dot-install-' + target.name)
        staged.mkdir(exist_ok=False)
        try:
            for member in members:
                source_prefix = prefix + path.rstrip('/') + '/'
                if not member.name.startswith(source_prefix) or member.isdir():
                    continue
                relative = pathlib.PurePosixPath(member.name[len(source_prefix):])
                if member.issym() or member.islnk() or not member.isfile() or '..' in relative.parts or relative.is_absolute():
                    raise ValueError('Unsupported archive entry: ' + member.name)
                output = staged.joinpath(*relative.parts)
                output.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(member) as stream:
                    output.write_bytes(stream.read())
            assert (staged / 'SKILL.md').is_file(), path
            (staged / '.dot-tool-source.json').write_text(json.dumps(source, indent=2) + '\n')
            staged.rename(target)
            print('Installed', target.name)
        finally:
            if staged.exists():
                shutil.rmtree(staged)
if args.browser:
    subprocess.run(['npx', '--yes', '@puppeteer/browsers@3.2.7', 'install', 'chrome@stable', '--path', str(pathlib.Path.home() / '.cache' / 'puppeteer')], check=True)
print('Tools installed. New skills are available on the next agent turn.')
