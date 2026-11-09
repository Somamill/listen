import hmac,re,time
from urllib.parse import urlparse,urljoin
from bs4 import BeautifulSoup
from flask import Blueprint,request,jsonify
from .goodreads_sync import TOKEN,STATE,save,read
from .discovery import STORE
from .covers import image_from
safari=Blueprint('safari_bridge',__name__)

def parse_book(html,page_title,url):
    soup=BeautifulSoup(html,'html.parser')
    title_node=soup.select_one('h1[data-testid="bookTitle"], h1#bookTitle, h1.BookPageTitleSection__title')
    author_node=soup.select_one('span.ContributorLink__name, a.authorName span, a.authorName')
    title=title_node.get_text(' ',strip=True) if title_node else ''
    author=author_node.get_text(' ',strip=True) if author_node else ''
    if not title:
        meta=soup.select_one('meta[property="og:title"]')
        candidate=meta.get('content','') if meta else page_title
        candidate=re.sub(r'\s*[|–—-]\s*Goodreads\s*$','',candidate,flags=re.I).strip()
        if ' by ' in candidate:
            title, fallback_author=candidate.rsplit(' by ',1)
            author=author or fallback_author
        else:title=candidate
    title=title.strip()[:300];author=author.strip()[:200]
    if not title or title.casefold() in ('goodreads','sign in','sign in to goodreads'):
        raise ValueError('Open a Goodreads book page in Safari, then try again.')
    return dict(title=title,author=author,goodreads=url,cover=image_from(soup.select_one('meta[property="og:image"], img.ResponsiveImage')))

def parse_shelf(html):
    soup=BeautifulSoup(html,'html.parser');books=[];seen=set()
    for row in soup.select('tr.bookalike.review, #booksBody tr, table#books tr.bookalike'):
        title_link=row.select_one('a.bookTitle, .title .value a[href*="/book/show/"]')
        author=row.select_one('a.authorName, .author .value a')
        if not title_link or not author:continue
        link=urljoin('https://www.goodreads.com',title_link.get('href',''))
        parsed=urlparse(link)
        if parsed.hostname not in ('www.goodreads.com','goodreads.com') or not parsed.path.startswith('/book/show/') or link in seen:continue
        seen.add(link)
        title=(title_link.get('title') or title_link.get_text(' ',strip=True)).strip()[:300]
        shelves=', '.join(a.get_text(' ',strip=True) for a in row.select('.shelves a[href*="shelf="], .shelf a[href*="shelf="]')) or 'your library'
        rating_node=row.select_one('.avg_rating .value');rating=rating_node.get_text(strip=True) if rating_node else ''
        try:rating=f'{float(rating):.2f}' if 0<float(rating)<=5 else ''
        except ValueError:rating=''
        books.append(dict(title=title,author=author.get_text(' ',strip=True)[:200],goodreads=link,shelf=shelves[:100],rating=rating,cover=image_from(row.select_one('.cover img, img.bookCover, img')),color=['moss','rust','slate','gold','rose','ink'][len(books)%6]))
        if len(books)>=500:break
    if not books:raise ValueError('No shelf books were found on this Safari page. Open My Books on Goodreads, or use a library CSV export.')
    return books

@safari.post('/goodreads/safari')
def capture():
    if not hmac.compare_digest(request.headers.get('X-Listen-Token',''),TOKEN.read_text().strip()):return jsonify(error='Unauthorized'),403
    if request.content_length and request.content_length>6*1024*1024:return jsonify(error='Page too large'),413
    data=request.get_json(silent=True)
    if not isinstance(data,dict):return jsonify(error='Invalid page data'),400
    url=str(data.get('url',''));parts=urlparse(url)
    if parts.scheme!='https' or parts.hostname not in ('www.goodreads.com','goodreads.com') or parts.username or parts.password:
        return jsonify(error='Open a Goodreads book or shelf in Safari first.'),400
    html=str(data.get('html',''))
    try:
        if re.match(r'^/book/show/\d+',parts.path):
            if data.get('mode')=='shelf':return jsonify(error='Open your Goodreads My Books shelf in Safari first.'),400
            book=parse_book(html,str(data.get('page_title','')),url)
            return jsonify(action='search',query=(book['title']+' '+book['author']).strip(),**book)
        if re.match(r'^/review/list/\d+',parts.path):
            if data.get('mode')=='book':return jsonify(error='Open a Goodreads book page in Safari first.'),400
            incoming=parse_shelf(html)
            # Merge this visible shelf page; keep books from other imported pages.
            existing=read(STORE,[])
            def identifier(book):
                match=re.search(r'/book/show/(\d+)',book.get('goodreads',''))
                return match.group(1) if match else (book.get('title','').casefold(),book.get('author','').casefold())
            by_id={identifier(b):b for b in existing}
            changed=False
            for b in incoming:
                if by_id.get(identifier(b))!=b:changed=True
                by_id[identifier(b)]=b
            library=list(by_id.values())[:2000]
            save(STORE,library)
            state={'state':'browser','last_sync':time.time(),'checked_at':time.time(),'count':len(library),'message':'Imported the Goodreads shelf page open in Safari. Open another shelf page to add it.','source':'Safari visible shelf page'}
            save(STATE,state)
            return jsonify(action='import',count=len(incoming),total=len(library),changed=changed)
        return jsonify(error='Sign in in Safari, then open a Goodreads book or My Books shelf.'),400
    except ValueError as exc:return jsonify(error=str(exc)),400


def own_shelf(soup):
    """Only the signed-in navigation's My Books link identifies the account."""
    for a in soup.select('header a, .siteHeader a, #header a, nav a'):
        if a.get_text(' ',strip=True).casefold() != 'my books':continue
        url=urljoin('https://www.goodreads.com',a.get('href',''))
        p=urlparse(url)
        if p.scheme=='https' and p.hostname in ('www.goodreads.com','goodreads.com'):
            match=re.fullmatch(r'/review/list/(\d+)(?:[-/].*)?',p.path)
            if match:return match.group(1)
    return None

@safari.post('/goodreads/window')
def window_page():
    """Native Goodreads window; no login form content is accepted."""
    if not hmac.compare_digest(request.headers.get('X-Listen-Token',''),TOKEN.read_text().strip()):return jsonify(error='Unauthorized'),403
    data=request.get_json(silent=True) or {};action=data.get('action')
    previous=read(STATE,{})
    if action in ('disconnect','connecting','needs-signin','unavailable'):
        state='disconnected' if action=='disconnect' else action
        save(STATE,dict(state=state,last_sync=previous.get('last_sync'),count=previous.get('count',0),message={'disconnected':'Goodreads disconnected. Your imported books stay on this Mac.','connecting':'Finish signing in in the Goodreads window inside listen. Your books will appear automatically.','needs-signin':'Sign in again in the Goodreads window inside listen.','unavailable':'Goodreads could not refresh. Your saved books are kept; try refreshing again.'}[state]))
        return jsonify(ok=True)
    url=str(data.get('url',''));p=urlparse(url)
    if p.scheme!='https' or p.hostname not in ('www.goodreads.com','goodreads.com') or p.username or p.password:return jsonify(error='Invalid Goodreads page'),400
    is_shelf=re.fullmatch(r'/review/list/(\d+)(?:[-/].*)?',p.path)
    if p.path not in ('','/') and not is_shelf and not re.fullmatch(r'/user/show/\d+[^/]*',p.path):return jsonify(error='Sign-in pages are never imported.'),400
    soup=BeautifulSoup(str(data.get('html','')),'html.parser');user=own_shelf(soup)
    if not user:return jsonify(action='wait',message='Waiting for Goodreads My Books navigation.'),200
    expected=str(data.get('user_id',''))
    if expected and expected!=user:return jsonify(error='The Goodreads account changed. Reconnect to choose this account.'),409
    base='https://www.goodreads.com/review/list/'+user
    if not is_shelf:
        return jsonify(action='navigate',url=base+'?shelf=all&per_page=100&page=1',user_id=user)
    if is_shelf.group(1)!=user:return jsonify(error='This is not your own Goodreads shelf.'),400
    try:incoming=parse_shelf(str(data.get('html','')))
    except ValueError:
        if not soup.select_one('table#books, #booksBody'):return jsonify(action='wait'),200
        incoming=[]
    try:page=int(data.get('page',1))
    except (TypeError,ValueError):return jsonify(error='Invalid shelf page'),400
    if page<1 or page>20:return jsonify(error='Invalid shelf page'),400
    # Accumulate a complete refresh separately, then swap the visible library atomically.
    pending=STORE.with_name('goodreads-pending.json')
    if page==1:accum=[]
    else:
        snapshot=read(pending,{})
        if snapshot.get('user_id')!=user or snapshot.get('page')!=page-1:return jsonify(error='Shelf refresh interrupted. Reconnect.'),409
        accum=snapshot.get('books',[])
    by_url={b['goodreads']:b for b in accum}
    for b in incoming:by_url[b['goodreads']]=b
    books=list(by_url.values())[:2000]
    next_link=soup.select_one('a.next_page:not(.disabled), a[rel="next"]')
    has_next=bool(next_link and next_link.get('href'))
    save(pending,dict(user_id=user,page=page,books=books))
    if has_next and page<20 and len(books)<2000:
        save(STATE,dict(state='syncing',count=len(books),last_sync=previous.get('last_sync'),message='Refreshing your Goodreads shelves…'))
        return jsonify(action='navigate',url=base+f'?shelf=all&per_page=100&page={page+1}',user_id=user,page=page+1)
    changed=books!=read(STORE,[]);save(STORE,books);pending.unlink(missing_ok=True)
    save(STATE,dict(state='connected',user_id=user,count=len(books),last_sync=time.time(),checked_at=time.time(),truncated=has_next,changed=changed,message='Goodreads connected inside listen. Safari is not needed. Shelves refresh every five minutes while the app is open.' if not has_next else 'Connected. First 2,000 books refreshed.'))
    return jsonify(action='complete',count=len(books),changed=changed,user_id=user)
