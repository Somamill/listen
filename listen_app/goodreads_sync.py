import hmac,json,os,re,secrets,tempfile,time
from pathlib import Path
from urllib.parse import urlparse
from flask import Blueprint,request,jsonify
from .discovery import STORE,goodreads_url
from .covers import safe_url
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
    return re.sub(r'[^a-z0-9]+',' ',(book.get('title','')+' '+book.get('author','')).casefold()).strip()[:500]

@sync.get('/goodreads/state')
def state():
    data=read(STATE,{'state':'needs-signin','message':'Sign in to Goodreads to refresh your shelves.'})
    if data.get('state')=='connected' and time.time()-data.get('last_sync',0)>600:
        data['state']='stale';data['message']='Waiting for your Goodreads session to refresh.'
    return jsonify(data)

@sync.post('/goodreads/sync')
def receive():
    if not hmac.compare_digest(request.headers.get('X-Listen-Token',''),TOKEN.read_text().strip()):return jsonify(error='Unauthorized'),403
    if request.content_length and request.content_length>3*1024*1024:return jsonify(error='Payload too large'),413
    data=request.get_json(silent=True) or {}
    old=read(STATE,{})
    kind=data.get('state')
    if kind not in ('connected','needs-signin','unavailable'):return jsonify(error='Invalid state'),400
    result={'state':kind,'checked_at':time.time(),'last_sync':old.get('last_sync'),'count':old.get('count',0),'truncated':bool(data.get('truncated',False))}
    messages={'needs-signin':'Sign in to Goodreads to connect your shelves.','unavailable':'Goodreads could not refresh your shelves. Open Goodreads and check your session.','connected':'Your Goodreads shelves are up to date.'}
    result['message']=messages[kind]
    if kind=='connected':
        rows=data.get('books')
        if not isinstance(rows,list):return jsonify(error='Missing books'),400
        books=[];seen=set()
        for row in rows[:500]:
            if not isinstance(row,dict):continue
            title=str(row.get('title','')).strip()[:300];author=str(row.get('author','')).strip()[:200]
            if not title or (title,author) in seen:continue
            seen.add((title,author))
            link=str(row.get('goodreads',''));parts=urlparse(link)
            if parts.scheme!='https' or parts.hostname not in ('goodreads.com','www.goodreads.com') or not parts.path.startswith('/book/show/'):
                link=goodreads_url(title,author)
            rating=str(row.get('rating',''))
            try:rating=f'{float(rating):.2f}' if 0<float(rating)<=5 else ''
            except (ValueError,TypeError):rating=''
            books.append(dict(title=title,author=author,goodreads=link,shelf=str(row.get('shelf','your library'))[:100],rating=rating,cover=safe_url(row.get('cover','')),color=['moss','rust','slate','gold','rose','ink'][len(books)%6]))
        changed=books!=read(STORE,[])
        save(STORE,books);result.update(last_sync=time.time(),count=len(books));result['changed']=changed
    save(STATE,result)
    return jsonify(ok=True,count=result['count'],changed=result.get('changed',False))

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
        key=book_key(book);book['track_key']=key;book['listening_state']=values.get(key,{}).get('state','want-to-listen');book['audio_status']=''
        title_tokens=re.findall(r'[a-z0-9]+',book['title'].casefold())
        if len(title_tokens)<2:continue
        for t in torrents:
            name_tokens=set(re.findall(r'[a-z0-9]+',t.get('name','').casefold()))
            if len(title_tokens)>=2 and set(title_tokens).issubset(name_tokens):
                pct=round(t.get('progress',0)*100)
                book['audio_status']=('Possible match · Ready to listen' if pct>=100 else f'Possible download match · {pct}%')
                break
    return books
