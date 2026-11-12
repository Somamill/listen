from __future__ import annotations
import copy,json,os,tempfile
from pathlib import Path,PureWindowsPath
from urllib.parse import urlparse

LANGUAGES=('English','German','French','Spanish','Italian','Dutch','Portuguese','Russian','Japanese')
DEFAULTS={
 'theme':'system','preferred_language':'English','languages':[], 'categories':[], 'excluded_categories':[], 'include_unknown_language':True,
 'catalog_host':'audiobookbay.lu','search_pages':2,
 'client':{'type':'magnet','url':'http://127.0.0.1:8080','username':'','category':'listen'},
 'downloads_folder':'','completed_folder':'','stage_incomplete':True,
 'browser':'default','auto_start_client':True,
}

def data_dir():
    return Path(os.environ.get('LISTEN_DATA_DIR',str(Path.home()/'Library/Application Support/listen')))

def atomic_json(path,data):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    fd,tmp=tempfile.mkstemp(dir=path.parent,prefix='.listen-')
    try:
        with os.fdopen(fd,'w') as f:json.dump(data,f,ensure_ascii=False,indent=2)
        os.replace(tmp,path)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)

def read_json(path,default):
    try:return json.loads(Path(path).read_text())
    except (OSError,ValueError):return copy.deepcopy(default)

def load():
    raw=read_json(data_dir()/'settings.json',{})
    config=copy.deepcopy(DEFAULTS)
    if isinstance(raw,dict):
        config.update({k:v for k,v in raw.items() if k in DEFAULTS})
        stored_client=raw.get('client',{})
        config['client']={**DEFAULTS['client'],**(stored_client if isinstance(stored_client,dict) else {})}
    if not config['downloads_folder']:config['downloads_folder']=str(Path.home()/'Downloads/listen')
    return config

def validate(payload):
    if not isinstance(payload,dict):raise ValueError('Invalid settings.')
    cfg=load()
    for k in DEFAULTS:
        if k in payload:cfg[k]=payload[k]
    if cfg['theme'] not in ('light','dark','system'):raise ValueError('Choose a supported theme.')
    if cfg['browser'] not in ('default','safari','chrome','firefox','edge','brave'):raise ValueError('Choose a supported browser.')
    if cfg['preferred_language'] not in LANGUAGES:raise ValueError('Choose a supported preferred language.')
    for key in ('languages','categories','excluded_categories'):
        if not isinstance(cfg[key],list) or len(cfg[key])>100:raise ValueError('Invalid filters.')
        cfg[key]=list(dict.fromkeys(str(v).strip()[:80] for v in cfg[key] if str(v).strip()))
    for key in ('include_unknown_language','stage_incomplete','auto_start_client'):
        if not isinstance(cfg[key],bool):raise ValueError('Invalid option.')
    try:cfg['search_pages']=int(cfg['search_pages'])
    except (ValueError,TypeError):raise ValueError('Choose 1 to 5 search pages.')
    if not 1<=cfg['search_pages']<=5:raise ValueError('Choose 1 to 5 search pages.')
    host=str(cfg['catalog_host']).strip().lower()
    if host not in ('audiobookbay.lu','audiobookbay.is'):raise ValueError('Choose a documented catalog host.')
    cfg['catalog_host']=host
    client=cfg['client']
    if not isinstance(client,dict) or client.get('type') not in ('qbittorrent','transmission','deluge','magnet'):raise ValueError('Choose a torrent client.')
    client={k:str(client.get(k,DEFAULTS['client'][k])).strip()[:500] for k in DEFAULTS['client']}
    if client['type']!='magnet':
        try:
            u=urlparse(client['url']);port=u.port
        except ValueError:raise ValueError('Use a valid client URL and port.')
        if u.scheme not in ('http','https') or not u.hostname or u.username or u.password or u.query or u.fragment or (port is not None and not 1<=port<=65535):raise ValueError('Use a client URL without embedded credentials.')
    cfg['client']=client
    remote=client['type']!='magnet' and urlparse(client['url']).hostname not in ('localhost','127.0.0.1','::1')
    for key in ('downloads_folder','completed_folder'):
        val=str(cfg[key]).strip()
        if val and (not (Path(val).is_absolute() or (remote and PureWindowsPath(val).is_absolute())) or '\x00' in val):raise ValueError('Choose an absolute destination folder.')
        cfg[key]=val
    return cfg

def credential_id(config=None):
    c=(config or load())['client']
    return c['type']+'|'+c['url']+'|'+c['username']

def get_password(config=None):
    import keyring
    try:return keyring.get_password('listen.torrent-client',credential_id(config)) or ''
    except keyring.errors.KeyringError:return ''

def save(payload):
    cfg=validate(payload)
    password=payload.get('password')
    if password is not None:
        import keyring
        try:
            if password:keyring.set_password('listen.torrent-client',credential_id(cfg),str(password))
            elif payload.get('clear_password'):
                try:keyring.delete_password('listen.torrent-client',credential_id(cfg))
                except keyring.errors.PasswordDeleteError:pass
        except keyring.errors.KeyringError as exc:raise ValueError('The system credential store is unavailable. Settings were not saved.') from exc
    atomic_json(data_dir()/'settings.json',cfg)
    return cfg
