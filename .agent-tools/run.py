"""Run a shared tool without adding dependencies to the app."""
import glob
import os
import pathlib
import subprocess
import sys

if len(sys.argv) < 2 or sys.argv[1] not in {'impeccable', 'hallmark', 'hyperframes'}:
    raise SystemExit('Usage: python3 .agent-tools/run.py impeccable|hallmark|hyperframes [arguments]')
tool, args = sys.argv[1], sys.argv[2:]
env = os.environ.copy()
if tool == 'hallmark':
    script = pathlib.Path.home() / '.agents/skills/hallmark/scripts/sloplint.mjs'
    if not script.is_file():
        raise SystemExit('Hallmark is missing. Run python3 .agent-tools/setup.py --browser')
    if not env.get('CHROME_PATH'):
        candidates = sorted(glob.glob(str(pathlib.Path.home() / '.cache/puppeteer/chrome/*/chrome-*/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing')) + glob.glob(str(pathlib.Path.home() / '.cache/puppeteer/chrome/*/chrome-linux*/chrome')) + glob.glob(str(pathlib.Path.home() / '.cache/puppeteer/chrome/*/chrome-win*/chrome.exe')))
        if candidates:
            env['CHROME_PATH'] = candidates[-1]
    cmd = ['node', str(script), *args]
else:
    cmd = [tool, *args]
try:
    result = subprocess.run(cmd, env=env)
except FileNotFoundError:
    raise SystemExit('Tool is missing. Run python3 .agent-tools/setup.py')
raise SystemExit(result.returncode)
