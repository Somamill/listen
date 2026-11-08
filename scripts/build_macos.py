#!/usr/bin/env python3
"""Build a self-contained listen.app and release archives on the current Mac architecture."""
import argparse,ast,hashlib,os,platform,plistlib,shutil,subprocess,sys,tempfile
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
    run([sys.executable,'-m','PyInstaller','--noconfirm','--clean','--onedir','--name','listen-server','--distpath',stage_root/'backend','--workpath',stage_root/'work','--specpath',stage_root,'--add-data',f'{ROOT}/listen_app/templates:listen_app/templates','--add-data',f'{ROOT}/listen_app/static:listen_app/static','--collect-submodules','keyring.backends','--copy-metadata','keyring','--copy-metadata','qbittorrent-api','--copy-metadata','transmission-rpc','--copy-metadata','deluge-web-client','listen_server.py'])
    app=stage_root/'listen.app'
    if app.exists():shutil.rmtree(app)
    contents=app/'Contents';(contents/'MacOS').mkdir(parents=True);(contents/'Resources').mkdir()
    shutil.copytree(dist/'backend/listen-server',contents/'Resources/server',symlinks=True)
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
