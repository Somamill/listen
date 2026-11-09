#!/usr/bin/env python3
"""Build a self-contained listen.app and release archives on the current Mac architecture."""
import argparse,ast,hashlib,json,os,platform,plistlib,shutil,signal,subprocess,sys,tempfile,time,urllib.request,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
VERSION=next(ast.literal_eval(node.value) for node in ast.parse((ROOT/'listen_app/__init__.py').read_text()).body if isinstance(node,ast.Assign) and any(isinstance(target,ast.Name) and target.id=='__version__' for target in node.targets))
def run(args,**kwargs):subprocess.run([str(v) for v in args],check=True,**kwargs)
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--dmg',action='store_true');args=parser.parse_args()
    if sys.platform!='darwin':raise SystemExit('Build the native app on macOS.')
    os.chdir(ROOT);os.environ.setdefault('MACOSX_DEPLOYMENT_TARGET','13.0')
    arch='arm64' if platform.machine()=='arm64' else 'x86_64'
    dist=ROOT/'dist';dist.mkdir(exist_ok=True)
    stage_root=Path(tempfile.mkdtemp(prefix='listen-build-'))
    os.environ['PYINSTALLER_CONFIG_DIR']=str(stage_root/'cache')
    os.environ.pop('PYTHONPYCACHEPREFIX',None)
    os.environ.pop('PYTHONDONTWRITEBYTECODE',None)
    os.environ['PYTHONPATH']=str(ROOT)
    run([sys.executable,'-m','PyInstaller','--noconfirm','--clean','--onedir','--name','listen-server','--distpath',stage_root/'backend','--workpath',stage_root/'work','--specpath',stage_root,'--paths',ROOT,'--add-data',f'{ROOT}/listen_app/templates:listen_app/templates','--add-data',f'{ROOT}/listen_app/static:listen_app/static','--collect-submodules','keyring.backends','--copy-metadata','keyring','--copy-metadata','qbittorrent-api','--copy-metadata','transmission-rpc','--copy-metadata','deluge-web-client','listen_server.py'])
    app=stage_root/'listen.app'
    if app.exists():shutil.rmtree(app)
    contents=app/'Contents';(contents/'MacOS').mkdir(parents=True);(contents/'Resources').mkdir()
    shutil.copytree(stage_root/'backend/listen-server',contents/'Resources/server',symlinks=True)
    shutil.copy2(ROOT/'native/AppIcon.icns',contents/'Resources/AppIcon.icns')
    for name in ['LICENSE','THIRD_PARTY_NOTICES.md']:
        if (ROOT/name).exists():shutil.copy2(ROOT/name,contents/'Resources'/name)
    from importlib.metadata import distributions
    licenses=contents/'Resources/licenses';licenses.mkdir()
    for distribution in distributions():
        name=distribution.metadata.get('Name','package').replace('/','_')
        for entry in distribution.files or []:
            base=Path(str(entry)).name.casefold()
            if base.startswith(('license','copying','notice','authors')):
                source=Path(distribution.locate_file(entry))
                if source.is_file():
                    relative=Path(*[part for part in Path(str(entry)).parts if part not in ('.','..','/')])
                    target=licenses/name/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
    if (ROOT/'docs/licenses').exists():shutil.copytree(ROOT/'docs/licenses',licenses/'python',dirs_exist_ok=True)
    info={'CFBundleExecutable':'listen','CFBundleIdentifier':'io.github.somamill.listen','CFBundleName':'listen.','CFBundleDisplayName':'listen.','CFBundleVersion':VERSION,'CFBundleShortVersionString':VERSION,'CFBundlePackageType':'APPL','CFBundleIconFile':'AppIcon','LSMinimumSystemVersion':'13.0','NSHighResolutionCapable':True,'NSAppleEventsUsageDescription':'Read the Goodreads book or bookshelf page you choose in Safari to find audiobook editions and import your reading list. Passwords and cookies stay in Safari.','NSAppTransportSecurity':{'NSAllowsLocalNetworking':True},'CFBundleURLTypes':[{'CFBundleURLName':'listen. Goodreads book handoff','CFBundleURLSchemes':['listen'],'CFBundleTypeRole':'Viewer'}]}
    (contents/'Info.plist').write_bytes(plistlib.dumps(info))
    run(['swiftc','native/Listen.swift','-o',contents/'MacOS/listen','-framework','AppKit','-framework','WebKit','-framework','LocalAuthentication'])
    ent=stage_root/'entitlements.plist';ent.write_bytes(plistlib.dumps({'com.apple.security.automation.apple-events':True}))
    # Remove Finder presentation metadata from generated build files only.
    # Preserve quarantine and all security-related attributes.
    for attribute in ('com.apple.FinderInfo','com.apple.ResourceFork'):
        subprocess.run(['xattr','-dr',attribute,str(app)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=False)
    # PyInstaller signs embedded binaries first; sign the outer native bundle last.
    run(['codesign','--force','--entitlements',ent,'--sign',os.environ.get('LISTEN_SIGN_IDENTITY','-'),app])
    run(['codesign','--verify','--deep','--strict',app])
    # Reject stale frozen bytecode before publishing a package.
    from PyInstaller.archive.readers import CArchiveReader
    import types
    archive_reader=CArchiveReader(str(contents/'Resources/server/listen-server'))
    frozen=archive_reader.open_embedded_archive('PYZ.pyz').extract('listen_app.server')
    entry=next(value for value in frozen.co_consts if isinstance(value,types.CodeType) and value.co_name=='main')
    if 'owner_pid' not in str(entry.co_consts):raise RuntimeError('Frozen service does not match the current launcher handshake.')
    # Exercise the actual frozen service/launcher protocol before making archives.
    check_root=stage_root/'service-check';check_root.mkdir()
    env=dict(os.environ,LISTEN_DATA_DIR=str(check_root),LISTEN_OWNER_PID=str(os.getpid()))
    log_path=stage_root/'service-check.log'
    with log_path.open('wb') as log:
        process=subprocess.Popen([str(contents/'Resources/server/listen-server')],env=env,stdout=log,stderr=log,start_new_session=True)
        try:
            connection_path=check_root/'connection.json'
            for _ in range(100):
                if connection_path.exists():break
                if process.poll() is not None:raise RuntimeError('Bundled service exited: '+log_path.read_text(errors='replace')[-2000:])
                time.sleep(.1)
            if not connection_path.exists():raise RuntimeError('Bundled service startup timed out.')
            connection=json.loads(connection_path.read_text())
            assert isinstance(connection['port'],int),'Service port must be numeric.'
            assert connection['owner_pid']==os.getpid(),'Service launcher identity mismatch.'
            url='http://127.0.0.1:'+str(connection['port'])+'/api/health'
            request=urllib.request.Request(url,headers={'X-Listen-Token':connection['token']})
            with urllib.request.urlopen(request,timeout=5) as response:assert json.load(response)['version']==VERSION
            base='http://127.0.0.1:'+str(connection['port'])
            def fresh_get(path):
                with urllib.request.urlopen(urllib.request.Request(base+path,headers={'X-Listen-Token':connection['token']}),timeout=8) as response:return response.read()
            prefs=json.loads(fresh_get('/api/settings'))
            assert prefs['client']['type']=='magnet','Fresh installs must not require a preconfigured Web UI.'
            assert prefs['languages']==[] and prefs['excluded_categories']==[] and prefs['completed_folder']=='','Personal preferences must not enter fresh packages.'
            for page in ('/','/discover','/settings','/status','/library'):
                html=fresh_get(page)
                assert b'Traceback' not in html and b'Invalid origin' not in html,page
            assert connection_path.stat().st_mode & 0o077 == 0,'Local connection data must be private.'

            try:urllib.request.urlopen(url,timeout=5)
            except urllib.error.HTTPError as exc:assert exc.code==401
            else:raise RuntimeError('Bundled service accepted an unauthenticated request.')
        finally:
            try:os.killpg(process.pid,signal.SIGTERM)
            except ProcessLookupError:pass
            process.wait(timeout=5)
    print('Bundled fresh-install pages, neutral defaults, startup, launcher identity, and authentication checks passed.')
    archive=dist/f'listen-{VERSION}-macOS-{arch}.zip';run(['ditto','-c','-k','--sequesterRsrc','--keepParent',app,archive])
    artifacts=[archive]
    if args.dmg:
        stage=stage_root/'dmg';stage.mkdir(parents=True,exist_ok=True)
        target=stage/'listen.app'
        if target.exists():shutil.rmtree(target)
        shutil.copytree(app,target,symlinks=True)
        link=stage/'Applications'
        if not link.exists():link.symlink_to('/Applications')
        dmg=dist/f'listen-{VERSION}-macOS-{arch}.dmg'
        if dmg.exists():dmg.unlink()
        run(['hdiutil','create','-volname','listen.','-srcfolder',stage,'-ov','-format','UDZO',dmg]);artifacts.append(dmg)
    (dist/f'SHA256SUMS-{arch}.txt').write_text(''.join(hashlib.sha256(a.read_bytes()).hexdigest()+'  '+a.name+'\n' for a in artifacts))
    (ROOT/'build').mkdir(exist_ok=True);(ROOT/'build/app-path.txt').write_text(str(app))
    print('App bundle:',app)
    print('Built:',*[str(a) for a in artifacts],sep='\n')
if __name__=='__main__':main()
