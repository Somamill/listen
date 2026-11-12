"""Catalog parsing adapted from JamesRy96/audiobookbay-automated (MIT)."""
import re,time
from urllib.parse import urljoin,urlparse,urlencode,parse_qs
import requests
from bs4 import BeautifulSoup
from . import settings
from .covers import image_from
UA={'User-Agent':'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'}
ALIASES={'english':'English','englisch':'English','german':'German','deutsch':'German','french':'French','français':'French','spanish':'Spanish','español':'Spanish','italian':'Italian','italiano':'Italian','dutch':'Dutch','nederlands':'Dutch','portuguese':'Portuguese','russian':'Russian','japanese':'Japanese'}
class CatalogError(RuntimeError):pass

def metadata(post):
    info=post.select_one('.postInfo');text=info.get_text(' ',strip=True) if info else ''
    match=re.search(r'Language:\s*(.*?)(?=\s*(?:Keywords|Category|Categories|Posted|Format|Bitrate|File Size):|$)',text,re.I|re.S)
    language=match.group(1).strip() if match else ''
    match=re.search(r'Categor(?:y|ies):\s*(.*?)(?=\s*(?:Language|Keywords|Posted|Format|Bitrate|File Size):|$)',text,re.I|re.S)
    category=match.group(1).strip() if match else ''
    labels=[a.get_text(' ',strip=True) for a in post.select('.postInfo a, a[rel~="tag"], .post-categories a, .tags a')]
    languages=[ALIASES.get(t.strip().casefold(),t.strip()) for t in re.split(r'[,/&+;]|\band\b',language,flags=re.I) if t.strip()]
    return {'language':' & '.join(languages) or 'Unknown','languages':languages,'category':category,'labels':labels}

def allowed(meta,cfg=None):
    cfg=cfg or settings.load();selected={s.casefold() for s in cfg['languages']}
    if selected:
        selected.add(cfg.get('preferred_language','English').casefold())
        if not meta['languages'] and not cfg['include_unknown_language']:return False
        if any(l.casefold() not in selected for l in meta['languages']):return False
    exclusions=[e.casefold().strip() for e in cfg['excluded_categories']]
    labels=[l.casefold().strip() for l in meta['labels']]
    category=meta['category'].casefold()
    if cfg.get('categories') and not any(t.casefold() in labels or re.search(r'(?<![\w-])'+re.escape(t.casefold())+r'(?![\w-])',category) for t in cfg['categories']):return False
    for excluded in exclusions:
        if excluded in labels or re.search(r'(?<!\w)'+re.escape(excluded)+r'(?!\w)',category):return False
    return True

CATALOG_HOSTS=frozenset({'audiobookbay.lu','audiobookbay.is'})

def valid_catalog_url(url):
    try:
        parsed=urlparse(url)
        return parsed.scheme=='https' and parsed.hostname in CATALOG_HOSTS and parsed.port in (None,443) and not parsed.username and not parsed.password
    except ValueError:return False

def _request(url):
    for attempt in range(2):
        try:response=requests.get(url,headers=UA,timeout=(4,10),allow_redirects=False)
        except requests.exceptions.SSLError as exc:raise CatalogError('The catalog’s secure connection could not be verified. Choose another approved catalog host in Settings or try again later.') from exc
        except (requests.Timeout,requests.ConnectionError) as exc:
            if attempt==0:time.sleep(.6);continue
            raise CatalogError('The catalog did not respond after a retry. Check your connection or try again shortly.') from exc
        if response.status_code in (500,502,503,504):
            retry_after=response.headers.get('Retry-After','')
            if attempt==0 and not retry_after:time.sleep(.6);continue
            raise CatalogError('The catalog’s search server is having a temporary problem. Your downloads are unaffected; try searching again shortly.')
        if response.status_code==429:raise CatalogError('The catalog is asking us to slow down. Wait a little before searching again.')
        if response.status_code==404:raise CatalogError('The catalog could not find this search page. Try a shorter book title or author.')
        if response.status_code in (401,403):raise CatalogError('The catalog refused this request. Open the catalog in your browser to check its access requirements.')
        response.raise_for_status()
        return response
    raise CatalogError('The catalog is temporarily unavailable. Please try again shortly.')

def fetch(url,cfg=None):
    cfg=cfg or settings.load()
    if not valid_catalog_url(url):raise CatalogError('Invalid catalog link.')
    search_term=parse_qs(urlparse(url).query).get('s')
    seen=set()
    try:
        for _ in range(6):
            if url in seen:raise CatalogError('The catalog is redirecting in a loop. Please try again later.')
            seen.add(url)
            response=_request(url)
            if 300<=response.status_code<400:
                location=response.headers.get('Location')
                if not location:raise CatalogError('The catalog returned an incomplete redirect. Please try again later.')
                target=urljoin(url,location)
                if not valid_catalog_url(target):raise CatalogError('The catalog redirected outside its approved HTTPS hosts. This address was blocked.')
                if search_term and parse_qs(urlparse(target).query).get('s')!=search_term:
                    raise CatalogError('The catalog dropped this search instead of returning results. Try a shorter book title or author.')
                url=target;continue
            soup=BeautifulSoup(response.text,'html.parser')
            soup._listen_catalog_url=url
            return soup
        raise CatalogError('The catalog redirected too many times. Please try again later.')
    except requests.RequestException as exc:raise CatalogError('The catalog returned an unexpected response. Please try again shortly.') from exc

def edition_key(book):
    # Keep author, subtitles, and series numbers in the identity; language is ranked separately.
    # Strip only explicit release/codec annotations, never arbitrary brackets.
    title=book['title'].casefold()
    title=re.sub(r'\b(?:unabridged|abridged|m4b|m4a|mp3|flac|aac|opus|\d{2,3}\s*kbps)\b',' ',title)
    title=re.sub(r'[\[({]\s*(?:retail|chapteri[sz]ed|repack|audiobook|\d{4})\s*[\])}]',' ',title)
    # Explicit language labels describe an edition, not a different book.
    labels='|'.join(re.escape(label) for label in ALIASES)
    title=re.sub(r'[\[({]\s*(?:'+labels+r')\s*[\])}]',' ',title)
    return ' '.join(re.findall(r'\w+',title))

def edition_quality(book):
    text=book['title'].casefold()
    fmt=book.get('format','').casefold()
    # M4B is convenient for audiobook players. Lossless follows, then MP3.
    rank=max((score for name,score in [('m4b',5),('flac',4),('m4a',3),('mp3',2),('opus',2),('aac',2)] if name in fmt),default=0)
    metadata=sum(bool(book.get(k)) and book[k] not in ('Unknown','Not listed') for k in ('cover','language','category','format','file_size','bitrate'))
    completeness=0 if re.search(r'(?<!un)abridged',text) else 2 if 'unabridged' in text else 1
    return completeness,rank,metadata

def preferred_editions(books,cfg=None):
    cfg=cfg or settings.load();preferred=cfg.get('preferred_language','English').casefold()
    def quality(book):
        languages={ALIASES.get(v.strip().casefold(),v.strip()).casefold() for v in re.split(r'[,/&+;]|\band\b',book.get('language',''),flags=re.I)}
        return (int(preferred in languages),*edition_quality(book))
    chosen={}
    for book in books:
        key=edition_key(book)
        if key not in chosen or quality(book)>quality(chosen[key]):chosen[key]=book
    return list(chosen.values())

def search(query,cfg=None):
    cfg=cfg or settings.load();results=[];seen=set()
    # The provider matches common subtitle/series words too broadly. Keep the main title.
    primary=re.split(r'[:(\[]',query,maxsplit=1)[0].strip() or query.strip()
    remote_query=' '.join(primary.lower().split())
    for page in range(1,cfg['search_pages']+1):
        path='/' if page==1 else f'/page/{page}/'
        try:soup=fetch('https://'+cfg['catalog_host']+path+'?'+urlencode({'s':remote_query}),cfg)
        except CatalogError:
            if results:break
            raise
        posts=soup.select('.post')
        if not posts:break
        for post in posts:
            a=post.select_one('.postTitle > h2 > a')
            if not a:continue
            meta=metadata(post)
            if not allowed(meta,cfg):continue
            base=getattr(soup,'_listen_catalog_url',None) or 'https://'+cfg['catalog_host']
            link=urljoin(base,a.get('href',''))
            if not valid_catalog_url(link) or link in seen:continue
            seen.add(link)
            text=post.get_text(' ',strip=True)
            def field(label):
                m=re.search(label+r':\s*([^\s]+(?:\s*(?:kbps|GB|MB|KB))?)',text,re.I)
                return m.group(1)[:40] if m else 'Not listed'
            results.append(dict(cover=image_from(post.select_one('.postContent img, .postContent p img, img')),title=a.get_text(' ',strip=True),link=link,language=meta['language'],category=meta['category'],format=field('Format'),file_size=field('File Size'),bitrate=field('Bitrate'),health={'kind':'unknown','label':'Health unknown','detail':'Live peer health is available only after the client connects. No tracker is contacted by this preview.'}))
    results=preferred_editions(results,cfg)
    normalize=lambda text:' '.join(re.findall(r'\w+',text.casefold()))
    wanted=normalize(query);core=normalize(primary)
    significant=set(wanted.split())-{'the','a','an','of','and','in','to','for','der','die','das','und','von'}
    results.sort(key=lambda b:(int(normalize(b['title']).startswith(core)),len(significant & set(normalize(b['title']).split())),int(wanted in normalize(b['title']))),reverse=True)
    return results

def magnet(details_url,cfg=None):
    cfg=cfg or settings.load();soup=fetch(details_url,cfg);post=soup.select_one('.post')
    if post is None or not allowed(metadata(post),cfg):raise CatalogError('This edition is excluded by your language or category filters, or its metadata is unavailable.')
    direct=post.select_one('a[href^="magnet:?"]')
    if direct:
        link=direct['href']
        if re.search(r'xt=urn:btih:(?:[0-9a-fA-F]{40}|[A-Z2-7]{32})(?:&|$)',link):return link
    row=soup.find('td',string=re.compile(r'Info Hash',re.I))
    sibling=row.find_next_sibling('td') if row else None
    hash=sibling.get_text(strip=True) if sibling else ''
    if not re.fullmatch(r'(?:[0-9a-fA-F]{40}|[A-Z2-7]{32})',hash):raise CatalogError('No valid torrent info hash was found on this catalog page.')
    trackers=[]
    for td in post.select('td'):
        value=td.get_text(strip=True)
        if re.match(r'^(?:udp|https?)://[^\s]+$',value) and value not in trackers:trackers.append(value)
    # Do not invent sources or contact trackers outside the torrent client.
    params=[('xt','urn:btih:'+hash)]+[('tr',t) for t in trackers[:30]]
    return 'magnet:?'+urlencode(params)
