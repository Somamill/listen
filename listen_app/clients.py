from __future__ import annotations
from urllib.parse import urlparse
from pathlib import Path
from . import settings
from .health import describe

class ClientError(RuntimeError):pass

def _endpoint(config):
    u=urlparse(config['client']['url'])
    return u, u.port or (443 if u.scheme=='https' else 80)

def _connect(config):
    c=config['client'];pw=settings.get_password(config)
    if c['type']=='qbittorrent':
        from qbittorrentapi import Client
        q=Client(host=c['url'],username=c['username'],password=pw,REQUESTS_ARGS={'headers':{'Referer':c['url'].rstrip('/')+'/'},'timeout':3},HTTPADAPTER_ARGS={'max_retries':0})
        q.auth_log_in();return q
    if c['type']=='transmission':
        from transmission_rpc import Client
        u,port=_endpoint(config)
        return Client(host=u.hostname,port=port,protocol=u.scheme,path=u.path if u.path not in ('','/') else '/transmission/rpc',username=c['username'] or None,password=pw or None,timeout=8)
    if c['type']=='deluge':
        from deluge_web_client import DelugeWebClient
        d=DelugeWebClient(url=c['url'],password=pw);d.login();return d
    return None

def torrents(config=None):
    cfg=config or settings.load();kind=cfg['client']['type']
    if kind=='magnet':return []
    try:
        client=_connect(cfg);result=[]
        if kind=='qbittorrent':
            for t in client.torrents_info():
                result.append(dict(id=t.hash,name=t.name,progress=t.progress,state=t.state,size=t.total_size,download_speed=t.dlspeed,upload_speed=t.upspeed,seeds=t.num_seeds,peers=t.num_leechs,availability=t.availability,save_path=t.save_path,content_path=t.get("content_path", "")))
        elif kind=='transmission':
            for t in client.get_torrents():
                result.append(dict(id=str(t.id),name=t.name,progress=t.percent_done,state=str(t.status),size=t.total_size,download_speed=t.rate_download,upload_speed=t.rate_upload,seeds=None,peers=t.peers_connected,availability=None,save_path=t.download_dir,content_path=str(Path(t.download_dir)/t.name)))
        else:
            response=client.get_torrents_status(filter_dict={},keys=['name','progress','state','total_size','download_payload_rate','upload_payload_rate','num_seeds','num_peers','distributed_copies','save_path'],timeout=8)
            for hash,t in (response.result or {}).items():
                result.append(dict(id=hash,name=t['name'],progress=t.get('progress',0)/100,state=t.get('state','unknown'),size=t.get('total_size',0),download_speed=t.get('download_payload_rate',0),upload_speed=t.get('upload_payload_rate',0),seeds=t.get('num_seeds'),peers=t.get('num_peers'),availability=t.get('distributed_copies'),save_path=t.get('save_path',''),content_path=str(Path(t.get('save_path',''))/t['name'])))
        for t in result:
            t['in_library']=in_library(t.get('save_path',''),cfg.get('completed_folder',''));t['health']=describe(t);t['progress_percent']=round(t['progress']*100,1);t['size_label']=format_bytes(t['size']);t['speed_label']=format_bytes(t['download_speed'])+'/s'
        return result
    except Exception as exc:raise ClientError('Could not connect to the torrent client. Check its URL, Web/RPC interface, and credentials in Settings.') from exc

def test(config=None):
    cfg=config or settings.load()
    if cfg['client']['type']=='magnet':return {'connected':True,'client':'Default magnet-link app','count':0,'handoff':True}
    rows=torrents(cfg)
    return {'connected':True,'client':cfg['client']['type'],'count':len(rows),'handoff':False}

def safe_title(title):
    import re
    return re.sub(r'[<>:"/\\|?*]','',str(title)).strip().strip('.')[:120] or 'Audiobook'

def add(magnet,title,destination='default',config=None):
    cfg=config or settings.load();kind=cfg['client']['type']
    if kind=='magnet':return {'handoff':True,'magnet':magnet,'message':'Open this magnet link in your chosen torrent client. The client controls its destination.'}
    if destination!='default':raise ClientError('Downloads finish locally first. Use Send to library after completion.')
    folder=cfg['downloads_folder']
    if not folder:raise ClientError('Choose this destination folder in Settings first.')
    u,_=_endpoint(cfg);local=u.hostname in ('127.0.0.1','localhost','::1')
    if local and destination=='default':Path(folder).mkdir(parents=True,exist_ok=True)
    if local and not Path(folder).is_dir():raise ClientError('The destination folder is unavailable. Check Settings and your cloud drive.')
    save_path=str(Path(folder)/safe_title(title));extra={}
    if cfg['stage_incomplete'] and local and kind in ('qbittorrent','deluge'):
        if not local:raise ClientError('Local staging is only supported for a torrent client on this Mac. Disable staging for a remote client.')
        staging=settings.data_dir()/'Incomplete';staging.mkdir(parents=True,exist_ok=True)
        extra={'download_path':str(staging),'use_download_path':True}
    try:
        c=_connect(cfg)
        if kind=='qbittorrent':c.torrents_add(urls=magnet,save_path=save_path,category=cfg['client']['category'],use_auto_torrent_management=False,**extra)
        elif kind=='transmission':
            if extra:raise ClientError('Per-download local staging is supported by qBittorrent and Deluge. Configure Transmission’s own incomplete directory or disable staging.')
            c.add_torrent(magnet,download_dir=save_path)
        else:
            from deluge_web_client import TorrentOptions
            options=TorrentOptions(download_location=extra.get('download_path',save_path),move_completed=bool(extra),move_completed_path=save_path if extra else None)
            c.add_torrent_magnet(magnet,torrent_options=options)
        return {'handoff':False,'message':'Added to '+kind+'. This download stays local until you choose Send to library.','save_path':save_path}
    except ClientError:raise
    except Exception as exc:raise ClientError('The client could not add this download. Check the connection and destination settings.') from exc

def privacy():
    cfg=settings.load()
    if cfg['client']['type']!='qbittorrent':return None
    try:
        p=_connect(cfg).app_preferences()
        return {k:p.get(k) for k in ('proxy_type','proxy_peer_connections','proxy_bittorrent','proxy_misc','proxy_hostname_lookup','dht','pex','lsd','upnp')}
    except Exception:return None

def format_bytes(value):
    value=float(value or 0)
    for unit in ('B','KB','MB','GB','TB'):
        if value<1024:return f'{value:.1f} {unit}'
        value/=1024
    return f'{value:.1f} PB'


def is_local(config=None):
    cfg=config or settings.load()
    if cfg['client']['type']=='magnet':return False
    return _endpoint(cfg)[0].hostname in ('localhost','127.0.0.1','::1')

def in_library(path,root):
    if not root:return False
    path=str(path).replace('\\','/').rstrip('/')
    root=str(root).replace('\\','/').rstrip('/')
    return path==root or path.startswith(root+'/')

def move_completed(torrent_id,config=None):
    cfg=config or settings.load()
    if cfg['client']['type']=='magnet':raise ClientError('Your torrent client controls file moves in magnet-handoff mode.')
    folder=cfg['completed_folder']
    if not folder:raise ClientError('Choose a library folder in Settings first.')
    rows=torrents(cfg)
    matches=[t for t in rows if str(t['id'])==str(torrent_id)]
    if not matches:raise ClientError('This torrent is no longer in the connected client. Check Local library for its files.')
    t=matches[0]
    if t['progress']<1:raise ClientError('Wait until this download is complete before sending it to the library.')
    if in_library(t['save_path'],folder):return {'message':'This torrent is already in your library.','already':True}
    if is_local(cfg):
        root=Path(folder)
        if not root.is_dir():raise ClientError('Your library folder is unavailable. Check Settings or your cloud drive.')
        target=root/Path(t.get('content_path') or t['name']).name
        if target.exists():raise ClientError('An item with this name already exists in your library. Nothing was overwritten.')
    try:
        c=_connect(cfg);kind=cfg['client']['type']
        if kind=='qbittorrent':c.torrents_set_location(location=folder,torrent_hashes=str(torrent_id))
        elif kind=='transmission':c.move_torrent_data(ids=[int(torrent_id)],location=folder,move=True)
        else:c.execute_call({'method':'core.move_storage','params':[[str(torrent_id)],folder]})
        return {'message':'Move requested in '+kind+'. The client will keep track of the new location. Refresh to check completion.','moving':True}
    except ClientError:raise
    except Exception as exc:raise ClientError('The torrent client could not move this item. Its files were not moved by listen.') from exc
