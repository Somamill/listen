"""Durable, local-only cleanup after a client has finished moving every file."""
import threading,time
from pathlib import Path
from . import settings
LOCK=threading.RLock()

def journal():return settings.data_dir()/'library-transfers.json'
def pending():return settings.read_json(journal(),{})
def manifest(source):
    source=Path(source)
    files=[source] if source.is_file() else list(source.rglob('*'))
    if source.is_symlink() or any(p.is_symlink() for p in files):raise ValueError('Symbolic links cannot be transferred automatically.')
    result={('.' if p==source else str(p.relative_to(source))):p.stat().st_size for p in files if p.is_file()}
    if not result:raise ValueError('No completed files were found.')
    return result

def record(torrent_id,cfg,source,target):
    with LOCK:
        jobs=pending();key=str(torrent_id)
        if key in jobs:raise ValueError('This transfer is already pending. Its torrent will be removed after verification.')
        jobs[key]={'client':cfg['client']['type'],'url':cfg['client']['url'],'source':str(source),'target':str(target),'folder':cfg['completed_folder'],'downloads':cfg['downloads_folder'],'files':manifest(source)}
        settings.atomic_json(journal(),jobs)

def forget(key):
    with LOCK:
        jobs=pending();jobs.pop(str(key),None);settings.atomic_json(journal(),jobs)

def finish_pending(cfg=None):
    from . import clients
    cfg=cfg or settings.load()
    if not clients.is_local(cfg):return
    jobs=pending()
    if not jobs:return
    rows={str(t['id']):t for t in clients.torrents(cfg)}
    for key,job in jobs.items():
        if job['client']!=cfg['client']['type'] or job['url']!=cfg['client']['url']:continue
        row=rows.get(key)
        if not row:continue # An external deletion is never grounds to delete files.
        if row['progress']<1 or not clients.in_library(row['save_path'],job['folder']):continue
        if any(s in row['state'].casefold() for s in ('moving','checking','error','missing')):continue
        source=Path(job['source']);target=Path(job['target'])
        # Require every original file at the destination with the same size, and
        # absent from the source. A partial copy never triggers torrent removal.
        verified=all((target if rel=='.' else target/rel).is_file() and (target if rel=='.' else target/rel).stat().st_size==size and not (source if rel=='.' else source/rel).exists() for rel,size in job['files'].items())
        if not verified:continue
        c=clients._connect(cfg)
        if job['client']=='qbittorrent':c.torrents_delete(torrent_hashes=key,delete_files=False)
        elif job['client']=='transmission':c.remove_torrent(ids=[int(key)],delete_data=False)
        else:c.execute_call({'method':'core.remove_torrent','params':[key,False]})
        # Only empty leftover directories may be removed; unexpected files stay.
        if source.is_dir():
            for p in sorted(source.rglob('*'),key=lambda p:len(p.parts),reverse=True):
                if p.is_dir() and not p.is_symlink():
                    try:p.rmdir()
                    except OSError:pass
            try:source.rmdir()
            except OSError:pass
        downloads=Path(job['downloads']).resolve()
        parent=source.parent
        while downloads in parent.resolve().parents:
            try:parent.rmdir()
            except OSError:break
            parent=parent.parent
        forget(key)

def monitor():
    while True:
        try:finish_pending()
        except Exception:pass # Keep the durable job for the next attempt/restart.
        time.sleep(5)
