"""Browser-independent, read-only Goodreads public shelf refresh."""
import re,time,threading
import xml.etree.ElementTree as ET
from urllib.parse import urlparse
import requests
from flask import Blueprint,request,jsonify
from .goodreads_sync import read,save,STATE
from .discovery import STORE
from .covers import safe_url
feed=Blueprint('goodreads_feed',__name__)
CONNECTION=STORE.with_name('goodreads-connection.json')
LOCK=threading.Lock()

def profile_id(value):
    p=urlparse(str(value))
    if p.scheme!='https' or p.hostname not in ('www.goodreads.com','goodreads.com') or p.username or p.password:return None
    m=re.fullmatch(r'/(?:user/show|review/list|review/list_rss)/(\d+)(?:-[^/]*)?/?',p.path)
    return m.group(1) if m else None

def parse_feed(raw):
    if b'<!DOCTYPE' in raw.upper() or b'<!ENTITY' in raw.upper():raise ValueError('Unsupported feed format.')
    root=ET.fromstring(raw)
    if root.tag!='rss' or root.find('channel') is None:raise ValueError('Goodreads did not provide a public shelf feed.')
    books=[]
    for item in root.findall('./channel/item'):
        text=lambda tag:(item.findtext(tag) or '').strip()
        title=text('title')[:300];author=text('author_name')[:200];book_id=text('book_id')
        if not title:continue
        link=text('link');p=urlparse(link)
        if p.scheme!='https' or p.hostname not in ('www.goodreads.com','goodreads.com') or not re.match(r'^/book/show/\d+',p.path):
            if not book_id.isdigit():continue
            link='https://www.goodreads.com/book/show/'+book_id
        books.append(dict(title=title,author=author,goodreads=link,cover=safe_url(text('book_large_image_url') or text('book_medium_image_url') or text('book_image_url')),shelf=text('user_shelves')[:100] or 'your library',rating=text('average_rating')[:10],color=['moss','rust','slate','gold','rose','ink'][len(books)%6]))
    return books

def fetch_books(user_id):
    books=[];seen=set();truncated=False
    for page in range(1,11):
        with requests.get('https://www.goodreads.com/review/list_rss/'+user_id,params={'shelf':'all','per_page':200,'page':page},timeout=(5,15),allow_redirects=False,stream=True,headers={'User-Agent':'listen public-shelf-sync'}) as response:
            if response.status_code!=200:raise ValueError('Goodreads public shelf is unavailable. Check the profile privacy or try again later.')
            chunks=[];size=0
            for chunk in response.iter_content(65536):
                size+=len(chunk)
                if size>6*1024*1024:raise ValueError('The Goodreads shelf feed is too large.')
                chunks.append(chunk)
            rows=parse_feed(b''.join(chunks))
        new=[b for b in rows if b['goodreads'] not in seen]
        for b in new:seen.add(b['goodreads']);books.append(b)
        if len(rows)<200:break
        if not new:
            truncated=True;break # Some feeds repeat page 1; never pretend it is a complete library.
        if page==10:truncated=True
    return books,truncated

def refresh(force=False):
    if not LOCK.acquire(blocking=False):return
    try:
        conn=read(CONNECTION,{})
        user=conn.get('user_id','')
        if not conn.get('enabled') or not re.fullmatch(r'\d+',user):return
        if not force and time.time()-conn.get('checked_at',0)<300:return
        old=read(STATE,{})
        try:
            books,truncated=fetch_books(user)
            if read(CONNECTION,{}).get('user_id')!=user or not read(CONNECTION,{}).get('enabled'):return
            changed=books!=read(STORE,[]);save(STORE,books)
            save(STATE,dict(state='connected',source='public-feed',user_id=user,last_sync=time.time(),count=len(books),truncated=truncated,changed=changed,message='Goodreads connected. Refreshes automatically without Safari.' if not truncated else 'Goodreads connected. The feed returned a limited selection of your books.'))
        except (requests.RequestException,ValueError,ET.ParseError):
            if read(CONNECTION,{}).get('enabled'):
                save(STATE,dict(state='needs-access',source='public-feed',last_sync=old.get('last_sync'),count=old.get('count',0),message='Could not read your public Goodreads shelf. Check the profile visibility or try again later. Your saved books are kept.'))
        conn=read(CONNECTION,{})
        if conn.get('user_id')==user:conn['checked_at']=time.time();save(CONNECTION,conn)
    finally:LOCK.release()

def connect(user):
    if not re.fullmatch(r'\d+',str(user)):raise ValueError('Invalid Goodreads profile.')
    save(CONNECTION,dict(enabled=True,user_id=str(user),checked_at=0))
    old=read(STATE,{})
    save(STATE,dict(state='syncing',count=old.get('count',0),last_sync=old.get('last_sync'),source='public-feed',message='Connecting directly to your Goodreads shelf…'))
    threading.Thread(target=refresh,args=(True,),daemon=True).start()

def start():
    def worker():
        while True:
            refresh();time.sleep(30)
    threading.Thread(target=worker,daemon=True).start()

@feed.post('/goodreads/feed/connect')
def connect_profile():
    user=profile_id((request.get_json(silent=True) or {}).get('url',''))
    if not user:return jsonify(error='Use your Goodreads profile or My Books URL.'),400
    connect(user);return jsonify(ok=True)

@feed.post('/goodreads/feed/refresh')
def refresh_profile():
    if not read(CONNECTION,{}).get('enabled'):return jsonify(error='Connect your Goodreads profile first.'),400
    threading.Thread(target=refresh,args=(True,),daemon=True).start();return jsonify(ok=True)

@feed.post('/goodreads/feed/disconnect')
def disconnect_profile():
    save(CONNECTION,dict(enabled=False))
    old=read(STATE,{});save(STATE,dict(state='disconnected',count=old.get('count',0),last_sync=old.get('last_sync'),message='Goodreads disconnected. Saved books remain on this Mac.'))
    return jsonify(ok=True)
