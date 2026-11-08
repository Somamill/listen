"""Metadata images, fetched through a restricted local cache (never arbitrary URLs)."""
import hashlib,io,os,time,re
from urllib.parse import urlparse,urljoin,parse_qs
import requests
from flask import Blueprint,request,send_file,abort
from . import settings
covers=Blueprint('covers',__name__)
HOSTS={'i.gr-assets.com','s.gr-assets.com','images.gr-assets.com','m.media-amazon.com','images-na.ssl-images-amazon.com','images-eu.ssl-images-amazon.com','covers.openlibrary.org'}

def safe_url(value):
    if not isinstance(value,str) or len(value)>2048:return ''
    try:
        p=urlparse(value)
        if p.scheme!='https' or p.port not in (None,443) or p.username or p.password:return ''
        if p.hostname in HOSTS:
            if p.hostname in {'i.gr-assets.com','s.gr-assets.com','images.gr-assets.com'}:
                value=re.sub(r'_S[XY]\d+_', '_SY600_', value)
                value=re.sub(r'(/books/\d+)s(/)',r'\1l\2',value)
            return value
        # Open Library redirects its cover images to Internet Archive cover ZIPs.
        if p.hostname=='archive.org' and re.fullmatch(r'/download/l_covers_\d+/l_covers_\d+_\d+\.zip/\d+-[SML]\.jpg',p.path):return value
        if re.fullmatch(r'ia\d+\.us\.archive\.org',p.hostname or '') and p.path=='/view_archive.php':
            q=parse_qs(p.query)
            if set(q)=={'archive','file'} and len(q['archive'])==len(q['file'])==1 and re.fullmatch(r'/\d+/items/l_covers_\d+/l_covers_\d+_\d+\.zip',q['archive'][0]) and re.fullmatch(r'\d+-[SML]\.jpg',q['file'][0]):return value
        return '' 
    except ValueError:return ''

def image_from(node):
    if node is None:return ''
    return safe_url(node.get('data-src') or node.get('src') or node.get('content') or '')

@covers.get('/cover')
def cover():
    url=safe_url(request.args.get('url',''))
    if not url:abort(400)
    cache=settings.data_dir()/'cover-cache';cache.mkdir(mode=0o700,exist_ok=True)
    path=cache/hashlib.sha256(url.encode()).hexdigest()
    if path.exists() and time.time()-path.stat().st_mtime<7*86400:
        raw=path.read_bytes()
    else:
        try:
            for _ in range(4):
                with requests.get(url,timeout=(4,8),allow_redirects=False,stream=True,headers={'User-Agent':'listen book-cover-cache'}) as response:
                    if response.is_redirect:
                        url=safe_url(urljoin(url,response.headers.get('Location','')))
                        if not url:abort(400)
                        continue
                    response.raise_for_status();chunks=[];size=0
                    for chunk in response.iter_content(65536):
                        size+=len(chunk)
                        if size>8*1024*1024:abort(413)
                        chunks.append(chunk)
                    raw=b''.join(chunks);break
            else:abort(502)
        except requests.RequestException:abort(502)
        if not mime(raw):abort(415)
        # Atomic, private cache; the original URL and browsing session are not stored.
        import tempfile
        fd,tmp=tempfile.mkstemp(dir=cache)
        try:
            with os.fdopen(fd,'wb') as f:f.write(raw)
            os.replace(tmp,path)
        finally:
            if os.path.exists(tmp):os.unlink(tmp)
    kind=mime(raw)
    if not kind:abort(415)
    return send_file(io.BytesIO(raw),mimetype=kind)

def mime(raw):
    if raw.startswith(b'\xff\xd8\xff'):return 'image/jpeg'
    if raw.startswith(b'\x89PNG\r\n\x1a\n'):return 'image/png'
    if raw.startswith(b'RIFF') and raw[8:12]==b'WEBP':return 'image/webp'
    return None
