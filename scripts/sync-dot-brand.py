"""Copy a checked-out public brand kit; only branding/dot is managed."""
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys

source = pathlib.Path(sys.argv[1]).resolve()
repo = pathlib.Path(__file__).resolve().parents[1]
sha = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
kit = source / 'kit'
# Never import symlinks or executable files from the upstream checkout.
files = sorted(p for p in kit.rglob('*') if p.is_file())
assert files and not any(p.is_symlink() for p in kit.rglob('*'))
assert all(p.suffix in {'.json', '.svg', '.md', '.css', '.ts', '.py'} or p.name == 'LICENSE' for p in files)
assert sum(p.stat().st_size for p in files) < 2_000_000
manifest = {'repository': 'Somamill/dot-brand-kit', 'commit': sha,
            'version': json.loads((kit / 'tokens.json').read_text())['version'],
            'files': {str(p.relative_to(kit)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
target = repo / 'branding' / 'dot'
if target.is_symlink():
    raise ValueError('Brand directory must not be a symlink')
if target.exists():
    shutil.rmtree(target)
shutil.copytree(kit, target)
(target / 'source.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Updated dot. kit to ' + sha)
