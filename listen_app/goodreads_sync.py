import json,os,re,secrets,tempfile,time
from flask import Blueprint,request,jsonify
from .discovery import STORE
sync=Blueprint('goodreads_sync',__name__)
ROOT=STORE.parent
STATE=ROOT/'goodreads-sync-state.json'
TRACKING=ROOT/'listening-progress.json'
TOKEN=ROOT/'service.token'
ROOT.mkdir(parents=True,exist_ok=True)
if not TOKEN.exists():
    fd=os.open(TOKEN,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as f:f.write(secrets.token_urlsafe(32))

def read(path,default):
    try:return json.loads(path.read_text())
    except (OSError,ValueError):return default

def save(path,data):
    fd,tmp=tempfile.mkstemp(dir=path.parent,prefix='.library-')
    try:
        with os.fdopen(fd,'w') as f:json.dump(data,f)
        os.replace(tmp,path)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)

def book_key(book):
    return re.sub(r'[^\w]+',' ',(book.get('title','')+' '+book.get('author','')).casefold()).strip()[:500]

@sync.get('/goodreads/state')
def state():
    data=read(STATE,{'state':'needs-signin','message':'Sign in to Goodreads to refresh your shelves.'})
    if data.get('state')=='connected' and time.time()-data.get('last_sync',0)>600:
        data['state']='stale';data['message']='Waiting for your Goodreads session to refresh.'
    return jsonify(data)

@sync.post('/reading/track')
def track():
    data=request.get_json(silent=True) or {};key=str(data.get('key',''))[:500];value=data.get('value')
    if not key or value not in ('want-to-listen','listening','finished'):return jsonify(error='Invalid progress'),400
    values=read(TRACKING,{});values[key]={'state':value,'updated_at':time.time()};save(TRACKING,values)
    return jsonify(ok=True)

def library_tracking(books):
    if not books:return []
    values=read(TRACKING,{})
    torrents=[]
    try:
        from . import clients
        torrents=clients.torrents()
    except clients.ClientError:pass
    for book in books:
        key=book_key(book);legacy=re.sub(r'[^a-z0-9]+',' ',(book.get('title','')+' '+book.get('author','')).casefold()).strip()[:500]
        book['track_key']=key;book['listening_state']=values.get(key,values.get(legacy,{})).get('state','want-to-listen');book['audio_status']=''
        title_tokens=re.findall(r'[a-z0-9]+',book['title'].casefold())
        if len(title_tokens)<2:continue
        for t in torrents:
            name_tokens=set(re.findall(r'[a-z0-9]+',t.get('name','').casefold()))
            if len(title_tokens)>=2 and set(title_tokens).issubset(name_tokens):
                pct=round(t.get('progress',0)*100)
                book['audio_status']=('Possible match · Ready to listen' if pct>=100 else f'Possible download match · {pct}%')
                break
    return books
