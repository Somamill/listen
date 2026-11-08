"""Catalog parsing adapted from JamesRy96/audiobookbay-automated (MIT)."""
import re
from urllib.parse import urljoin,urlparse,urlencode
import requests
from bs4 import BeautifulSoup
from . import settings
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
        if not meta['languages'] and not cfg['include_unknown_language']:return False
        if any(l.casefold() not in selected for l in meta['languages']):return False
    exclusions=[e.casefold().strip() for e in cfg['excluded_categories']]
    labels=[l.casefold().strip() for l in meta['labels']]
    category=meta['category'].casefold()
    if cfg.get('categories') and not any(t.casefold() in labels or re.search(r'(?<![\w-])'+re.escape(t.casefold())+r'(?![\w-])',category) for t in cfg['categories']):return False
    for excluded in exclusions:
        if excluded in labels or re.search(r'(?<!\w)'+re.escape(excluded)+r'(?!\w)',category):return False
    return True

def fetch(url,cfg=None):
    cfg=cfg or settings.load();parsed=urlparse(url)
    if parsed.scheme!='https' or parsed.hostname!=cfg['catalog_host'] or parsed.username or parsed.password:raise CatalogError('Invalid catalog link.')
    try:
        response=requests.get(url,headers=UA,timeout=20,allow_redirects=False)
        response.raise_for_status()
        if 300<=response.status_code<400:raise CatalogError('The catalog redirected to another address. Check its host in Settings.')
        return BeautifulSoup(response.text,'html.parser')
    except requests.RequestException as exc:raise CatalogError('The catalog is unavailable. Try again later; certificate validation stays enabled.') from exc

def search(query,cfg=None):
    cfg=cfg or settings.load();results=[];seen=set()
    for page in range(1,cfg['search_pages']+1):
        try:soup=fetch('https://'+cfg['catalog_host']+f'/page/{page}/?'+urlencode({'s':query}),cfg)
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
            link=urljoin('https://'+cfg['catalog_host'],a.get('href',''))
            if urlparse(link).hostname!=cfg['catalog_host'] or link in seen:continue
            seen.add(link)
            text=post.get_text(' ',strip=True)
            def field(label):
                m=re.search(label+r':\s*([^\s]+(?:\s*(?:kbps|GB|MB|KB))?)',text,re.I)
                return m.group(1)[:40] if m else 'Not listed'
            results.append(dict(title=a.get_text(' ',strip=True),link=link,language=meta['language'],category=meta['category'],format=field('Format'),file_size=field('File Size'),bitrate=field('Bitrate'),health={'kind':'unknown','label':'Health unknown','detail':'Live peer health is available only after the client connects. No tracker is contacted by this preview.'}))
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
