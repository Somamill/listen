from __future__ import annotations
import argparse,hashlib,hmac,threading,json,logging,os,secrets,time
from urllib.parse import urlparse,urljoin
from flask import Flask,request,render_template,jsonify
from . import __version__,settings,catalog,clients


def same_secret(value,expected):
    return isinstance(value,str) and hmac.compare_digest(value.encode('utf-8'),expected.encode('utf-8'))

def create_app():
    app=Flask(__name__);app.config['MAX_CONTENT_LENGTH']=6*1024*1024
    root=settings.data_dir();root.mkdir(parents=True,exist_ok=True)
    token_file=root/'service.token'
    if not token_file.exists():
        fd=os.open(token_file,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,'w') as f:f.write(secrets.token_urlsafe(32))
    token=token_file.read_text().strip()
    app.config['SERVICE_TOKEN']=token;app.config['BOUND_PORT']=0
    from .covers import covers
    app.register_blueprint(covers)
    csrf=hmac.new(token.encode(),b'listen.form.csrf',hashlib.sha256).hexdigest()
    from .discovery import discovery
    from .goodreads_sync import sync
    from .safari_bridge import safari,parse_book
    app.register_blueprint(discovery);app.register_blueprint(sync);app.register_blueprint(safari)

    @app.before_request
    def protect_local_service():
        port=app.config['BOUND_PORT']
        if request.host != f'127.0.0.1:{port}':return 'Invalid host',403
        provided=request.headers.get('X-Listen-Token') or request.cookies.get('listen_session','')
        if not same_secret(provided,token):return 'Open listen. to use this local service.',401
        if request.method not in ('GET','HEAD','OPTIONS'):
            origin=request.headers.get('Origin');referer=request.headers.get('Referer','')
            allowed=f'http://127.0.0.1:{port}'
            native_auth=same_secret(request.headers.get('X-Listen-Token',''),token)
            same_origin=(origin==allowed or (origin in (None,'null') and referer.startswith(allowed+'/')))
            form_auth=same_secret(request.headers.get('X-Listen-CSRF') or request.form.get('_csrf',''),csrf)
            if origin not in (None,'null',allowed):return 'Invalid origin',403
            if not (same_origin or native_auth or form_auth):return 'Invalid origin',403
        if request.is_json and request.method not in ('GET','HEAD','OPTIONS') and not isinstance(request.get_json(silent=True),dict):return jsonify(error='Use a JSON object for this action.',message='Use a JSON object for this action.'),400

    @app.after_request
    def response_security(response):
        if same_secret(request.headers.get('X-Listen-Token',''),token):
            response.set_cookie('listen_session',token,httponly=True,samesite='Strict',path='/')
        response.headers['X-Content-Type-Options']='nosniff'
        response.headers['X-Frame-Options']='DENY'
        response.headers['Referrer-Policy']='same-origin'
        response.headers['Content-Security-Policy']="default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"
        response.headers['Cache-Control']='no-store'
        return response

    @app.context_processor
    def common():return {'config':settings.load(),'version':__version__,'csrf_token':csrf,'welcomed':bool(settings.read_json(root/'welcome.json',{}).get('dismissed'))}

    @app.get('/api/health')
    def health():return jsonify(app='listen.',version=__version__)

    @app.post('/api/welcome')
    def dismiss_welcome():
        settings.atomic_json(root/'welcome.json',{'dismissed':True})
        return jsonify(ok=True)

    @app.route('/',methods=['GET','POST'])
    def search():
        books=[];query='';source_book=None;error=None
        if request.method=='POST':
            query=request.form.get('query','').strip()[:500]
            title=request.form.get('goodreads_title','').strip()[:300];author=request.form.get('goodreads_author','').strip()[:200]
            if title:source_book={'title':title,'author':author}
            if query:
                try:
                    books=catalog.search(query)
                    if source_book:
                        import difflib,re
                        clean=lambda s:' '.join(re.findall(r'\w+',s.casefold()))
                        wanted=clean(title)
                        books.sort(key=lambda b:(int(wanted in clean(b['title'])),int(bool(author) and clean(author) in clean(b['title'])),difflib.SequenceMatcher(None,wanted,clean(b['title'])).ratio()),reverse=True)
                except catalog.CatalogError as exc:error=str(exc)
        return render_template('search.html',books=books,query=query,source_book=source_book,error=error)

    @app.post('/api/client/ready')
    def prepare_client():
        try:return jsonify(clients.prepare())
        except clients.ClientError as exc:return jsonify(message=str(exc)),400

    @app.post('/send')
    def send():
        d=request.get_json(silent=True)
        if not isinstance(d,dict) or not d.get('link') or not d.get('title'):return jsonify(message='Choose a catalog result first.'),400
        try:
            magnet=catalog.magnet(str(d['link']))
            return jsonify(clients.add(magnet,str(d['title']),d.get('destination','default')))
        except (catalog.CatalogError,clients.ClientError) as exc:return jsonify(message=str(exc)),400

    @app.get('/status')
    def status():
        return render_template('status.html',torrents=[],error=None)

    library_scan={'items':[],'error':None,'scanning':False,'updated':0}
    scan_lock=threading.Lock()
    @app.get('/library')
    def library_page():
        return render_template('library.html',items=[],error=None)

    @app.get('/api/library')
    def local_library():
        with scan_lock:
            if not library_scan['scanning'] and time.time()-library_scan['updated']>15:
                library_scan['scanning']=True
                def scan():
                    from . import library
                    try:rows,error=library.items()
                    except Exception:rows,error=[],'The downloads folder could not be read. Check its access in Settings.'
                    with scan_lock:library_scan.update(items=rows,error=error,scanning=False,updated=time.time())
                threading.Thread(target=scan,daemon=True).start()
            return jsonify(library_scan)

    @app.post('/library/transfer')
    def transfer_library():
        from . import library
        data=request.get_json(silent=True) or {}
        if not library.TRANSFER_LOCK.acquire(blocking=False):return jsonify(error='Another library transfer is running. Please wait.'),409
        try:
            if data.get('torrent_id') is not None:result=clients.move_completed(data['torrent_id'])
            else:result=library.transfer(data.get('relative'))
            return jsonify(result)
        except clients.ClientError as exc:return jsonify(error=str(exc)),400
        finally:library.TRANSFER_LOCK.release()

    @app.get('/api/torrents')
    def api_torrents():
        try:return jsonify(torrents=clients.torrents(),client=settings.load()['client']['type'])
        except clients.ClientError as exc:return jsonify(error=str(exc)),503

    @app.get('/connection')
    def connection():
        try:return jsonify(clients.test())
        except clients.ClientError as exc:return jsonify(connected=False,message=str(exc),count=0,client=settings.load()['client']['type'])

    @app.get('/settings')
    def settings_page():return render_template('settings.html')

    @app.route('/api/settings',methods=['GET','POST'])
    def api_settings():
        if request.method=='GET':return jsonify(settings.load())
        try:
            result=settings.save(request.get_json(silent=True))
            return jsonify(ok=True,settings=result)
        except ValueError as exc:return jsonify(error=str(exc)),400

    @app.get('/api/update')
    def check_update():
        try:
            import requests
            from packaging.version import Version,InvalidVersion
            response=requests.get('https://api.github.com/repos/Somamill/listen/releases',params={'per_page':10},headers={'Accept':'application/vnd.github+json'},timeout=10)
            response.raise_for_status()
            candidates=[]
            for release in response.json():
                if release.get('draft'):continue
                url=release.get('html_url','')
                if not url.startswith('https://github.com/Somamill/listen/releases/'):continue
                try:candidates.append((Version(release.get('tag_name','').lstrip('v')),release))
                except InvalidVersion:continue
            if not candidates:return jsonify(current=__version__,available=False,message='No public release is available yet.')
            version,release=max(candidates,key=lambda row:row[0])
            return jsonify(current=__version__,latest=str(version),available=version>Version(__version__),url=release['html_url'],prerelease=bool(release.get('prerelease')),message='A newer release is available.' if version>Version(__version__) else 'You are using the latest published version.')
        except Exception:return jsonify(error='Could not check GitHub releases. Please try again later.'),503

    @app.post('/api/folder')
    def choose_folder():
        data=request.get_json(silent=True) or {};key=data.get('kind');path=data.get('path')
        if key not in ('downloads_folder','completed_folder') or not isinstance(path,str):return jsonify(error='Invalid folder.'),400
        try:settings.save({key:path});return jsonify(ok=True,path=path)
        except ValueError as exc:return jsonify(error=str(exc)),400

    @app.get('/api/privacy')
    def privacy():return jsonify(settings=clients.privacy())

    @app.post('/goodreads/link')
    def goodreads_link():
        data=request.get_json(silent=True) or {};link=str(data.get('url',''));u=urlparse(link)
        if u.scheme!='https' or u.hostname not in ('www.goodreads.com','goodreads.com') or not u.path.startswith('/book/show/') or u.username or u.password:return jsonify(error='Paste a Goodreads book URL.'),400
        title=str(data.get('title','')).strip()[:300];author=str(data.get('author','')).strip()[:200]
        try:
            if not title:
                import requests
                url=link
                for _ in range(4):
                    response=requests.get(url,headers=catalog.UA,timeout=15,allow_redirects=False)
                    if response.is_redirect:
                        url=urljoin(url,response.headers.get('Location',''));target=urlparse(url)
                        if target.scheme!='https' or target.hostname not in ('www.goodreads.com','goodreads.com'):raise ValueError('Open the Goodreads book in your browser and use the bookmarklet, or enter its title manually.')
                        continue
                    response.raise_for_status();book=parse_book(response.text,'',url);title=book['title'];author=book['author'];break
                if not title:raise ValueError('Enter the book title and author to search.')
            return jsonify(action='search',title=title,author=author,goodreads=link,query=(title+' '+author).strip())
        except Exception:return jsonify(error='Goodreads did not provide a readable public page. Use the browser bookmarklet or enter the title and author manually.'),400

    return app

def main():
    parser=argparse.ArgumentParser(description='listen. private loopback service')
    parser.add_argument('--port',type=int,default=0);args=parser.parse_args()
    app=create_app()
    from waitress import create_server
    service=create_server(app,host='127.0.0.1',port=args.port,threads=6)
    port=int(service.effective_port);app.config['BOUND_PORT']=port
    settings.atomic_json(settings.data_dir()/'connection.json',{'port':port,'pid':os.getpid(),'owner_pid':int(os.environ.get('LISTEN_OWNER_PID','0')),'token':app.config['SERVICE_TOKEN'],'version':__version__})
    owner=int(os.environ.get('LISTEN_OWNER_PID','0'))
    if owner:
        def watch_owner():
            while True:
                time.sleep(2)
                try:os.kill(owner,0)
                except ProcessLookupError:os._exit(0)
                except PermissionError:pass
        threading.Thread(target=watch_owner,daemon=True).start()
    logging.getLogger('waitress').setLevel(logging.ERROR)
    try:service.run()
    finally:
        path=settings.data_dir()/'connection.json'
        if path.exists():path.unlink()

if __name__=='__main__':main()
