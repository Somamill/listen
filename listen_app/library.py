"""Explicit, user-directed transfers from local downloads to a library folder."""
import shutil,threading
from pathlib import Path
from . import settings,clients
AUDIO={'.mp3','.m4b','.m4a','.aac','.flac','.ogg','.opus','.wav','.aiff','.alac','.wma'}
TRANSFER_LOCK=threading.Lock()

def has_audio(path):
    if path.is_file():return path.suffix.casefold() in AUDIO
    if not path.is_dir() or path.is_symlink():return False
    import os
    count=0
    for root,dirs,files in os.walk(path,followlinks=False):
        relative=Path(root).relative_to(path)
        dirs[:]=[d for d in dirs if not d.startswith('.') and not (Path(root)/d).is_symlink()] if len(relative.parts)<3 else []
        for f in files:
            count+=1
            if Path(f).suffix.casefold() in AUDIO:return True
            if count>=1500:return False
    return False

def associations(path,rows):
    source=path.resolve();matched=[]
    for row in rows:
        content=row.get('content_path')
        if not content:continue
        target=Path(content).resolve()
        if target==source or source in target.parents or target in source.parents:matched.append(row)
    return matched

def items(config=None):
    cfg=config or settings.load()
    if not clients.is_local(cfg):return [],'Local file scanning is available for a directly connected torrent client on this Mac. Magnet handoff and remote clients manage their files themselves.'
    root=Path(cfg['downloads_folder']).expanduser()
    if not root.is_dir():return [],None
    try:rows=clients.torrents(cfg);error=None
    except clients.ClientError as exc:rows=[];error=str(exc)
    result=[]
    for child in sorted(root.iterdir(),key=lambda p:p.name.casefold()):
        if child.name.startswith('.') or child.is_symlink() or not has_audio(child):continue
        linked=associations(child,rows)
        ready=not error and all(t['progress']>=1 for t in linked)
        result.append({'name':child.name,'relative':child.name,'ready':ready,'linked':bool(linked),'status':('Client unavailable — transfer disabled' if error else 'Still downloading' if not ready else 'Completed in your client' if linked else 'Local item — confirm it is complete'),'torrent_id':linked[0]['id'] if len(linked)==1 else None})
        if len(result)>=200:break
    return result,error

def transfer(relative,config=None):
    cfg=config or settings.load()
    if not clients.is_local(cfg):raise clients.ClientError('Use your client’s move operation for this connection.')
    if not isinstance(relative,str) or not relative or relative in ('.','..') or '/' in relative or '\\' in relative or '\x00' in relative:raise clients.ClientError('Choose an item from your local downloads.')
    root=Path(cfg['downloads_folder']).resolve();source=root/relative
    if source.is_symlink() or source.resolve().parent!=root or not source.exists() or not has_audio(source):raise clients.ClientError('This local audiobook is unavailable.')
    if not cfg['completed_folder']:raise clients.ClientError('Choose a library folder in Settings first.')
    destination_root=Path(cfg['completed_folder']).resolve()
    if not destination_root.is_dir():raise clients.ClientError('The library folder is unavailable. Check iCloud Drive or your selected destination.')
    target=destination_root/source.name
    if target.exists():raise clients.ClientError('An item with this name already exists in your library. Nothing was overwritten.')
    if source==destination_root or source in destination_root.parents:raise clients.ClientError('Choose a library folder outside this download.')
    rows=clients.torrents(cfg)
    linked=associations(source,rows)
    if any(row['progress']<1 for row in linked):raise clients.ClientError('This item is still downloading. Wait for completion.')
    if len(linked)>1:raise clients.ClientError('This folder contains multiple managed torrents. Send them individually from Downloads.')
    if linked:return clients.move_completed(linked[0]['id'],cfg)
    # No connected torrent references this item. Use a normal filesystem move.
    try:shutil.move(str(source),str(target))
    except OSError as exc:raise clients.ClientError('The filesystem move could not finish. Check the source and destination folders before retrying.') from exc
    return {'message':'Moved to your library folder. iCloud will sync it according to your Mac’s settings.','moved':True}
