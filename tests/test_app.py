import copy,io,json,os,tempfile,unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch,Mock

TEMP=tempfile.TemporaryDirectory();os.environ['LISTEN_DATA_DIR']=TEMP.name
from listen_app import settings,catalog,clients
from listen_app.server import create_app
from listen_app.health import describe
from listen_app.safari_bridge import parse_book,parse_shelf
from bs4 import BeautifulSoup

class ListenTests(unittest.TestCase):
    def setUp(self):
        for name in ['settings.json','goodreads-library.json','goodreads-sync-state.json','listening-progress.json']:(Path(TEMP.name)/name).unlink(missing_ok=True)
        self.app=create_app();self.app.config['BOUND_PORT']=58432;self.client=self.app.test_client();self.base='http://127.0.0.1:58432'
        self.headers={'X-Listen-Token':self.app.config['SERVICE_TOKEN'],'Origin':self.base,'Referer':self.base+'/discover'}
        self.cfg=copy.deepcopy(settings.DEFAULTS);self.cfg['downloads_folder']=TEMP.name;self.cfg['completed_folder']=TEMP.name
        settings.atomic_json(Path(TEMP.name)/'settings.json',{'downloads_folder':str(Path(TEMP.name)/'downloads')})
    def get(self,path,headers=None):return self.client.get(path,base_url=self.base,headers=self.headers if headers is None else headers)
    def post(self,path,data=None,**kwargs):return self.client.post(path,base_url=self.base,headers=self.headers,json=data,**kwargs)
    def meta(self,lang='English',category='History',tag=''):
        p=BeautifulSoup(f'<div class="post"><h2>A book title</h2><div class="postInfo">Category: <a>{category}</a> Language: {lang} Keywords: <a rel="tag">{tag}</a></div></div>','html.parser').div
        return catalog.metadata(p)
    def test_auth_host_csrf_and_cookie(self):
        self.assertEqual(self.get('/discover',{}).status_code,401)
        response=self.get('/discover');self.assertEqual(response.status_code,200)
        self.assertIn('HttpOnly',response.headers['Set-Cookie']);self.assertIn('SameSite=Strict',response.headers['Set-Cookie'])
        self.assertEqual(self.client.get('/discover',base_url='http://evil.example:58432',headers=self.headers).status_code,403)
        self.assertEqual(self.client.post('/api/settings',base_url=self.base,headers={'X-Listen-Token':self.app.config['SERVICE_TOKEN'],'Origin':'https://evil.example'},json={}).status_code,403)
    def test_native_posts_and_same_origin_web_forms(self):
        self.assertEqual(self.get('/api/health').headers['Referrer-Policy'],'same-origin')
        response=self.client.post('/api/settings',base_url=self.base,headers={'X-Listen-Token':self.app.config['SERVICE_TOKEN']},json={'theme':'dark'})
        self.assertEqual(response.status_code,200)
        self.get('/discover')
        with patch.object(catalog,'search',return_value=[]):
            response=self.client.post('/',base_url=self.base,headers={'Referer':self.base+'/discover','Origin':'null'},data={'query':'Synthetic book'})
            self.assertEqual(response.status_code,200)
        response=self.client.post('/api/settings',base_url=self.base,headers={'Origin':'https://evil.example'},json={'theme':'light'})
        self.assertEqual(response.status_code,403)
    def test_webkit_form_without_origin_uses_page_csrf(self):
        response=self.get('/');soup=BeautifulSoup(response.get_data(as_text=True),'html.parser')
        token=soup.select_one('meta[name="listen-csrf"]')['content']
        with patch.object(catalog,'search',return_value=[]):
            response=self.client.post('/',base_url=self.base,data={'query':'Test','_csrf':token})
            self.assertEqual(response.status_code,200)
        self.assertEqual(self.client.post('/api/settings',base_url=self.base,json={}).status_code,403)
        self.assertEqual(self.client.post('/api/settings',base_url=self.base,headers={'Origin':'https://evil.example','X-Listen-CSRF':token},json={}).status_code,403)

    def test_goodreads_browser_bootstrap_starts_independent_feed(self):
        header='<header><a href="/review/list/123-test">My Books</a></header>'
        with patch('listen_app.goodreads_feed.connect') as connect:
            result=self.post('/goodreads/connection',{'url':'https://www.goodreads.com/','html':header})
            self.assertEqual(result.json['action'],'background');connect.assert_called_once_with('123')
        result=self.post('/goodreads/connection',{'url':'https://www.goodreads.com/user/sign_in','html':header})
        self.assertEqual(result.status_code,400)
    def test_goodreads_feed_metadata_and_profile_validation(self):
        from listen_app.goodreads_feed import profile_id,parse_feed
        self.assertEqual(profile_id('https://www.goodreads.com/user/show/123-name'),'123')
        self.assertIsNone(profile_id('https://evil.example/user/show/123'))
        rows=parse_feed(b'<rss><channel><item><title>Example</title><author_name>Author</author_name><book_id>42</book_id><book_image_url>https://i.gr-assets.com/a.jpg</book_image_url></item></channel></rss>')
        self.assertEqual(rows[0]['goodreads'],'https://www.goodreads.com/book/show/42');self.assertIn('a.jpg',rows[0]['cover'])
        with self.assertRaises(ValueError):parse_feed(b'<!DOCTYPE rss><rss/>')
        with patch('listen_app.goodreads_feed.connect') as connect:
            self.assertEqual(self.post('/goodreads/feed/connect',{'url':'https://www.goodreads.com/user/show/123'}).status_code,200);connect.assert_called_once_with('123')

    def test_native_goodreads_window_pages_and_session_boundary(self):
        header='<header><a href="/review/list/123-name">My Books</a></header>'
        result=self.post('/goodreads/window',{'url':'https://www.goodreads.com/','html':header})
        self.assertEqual(result.json['action'],'navigate');self.assertEqual(result.json['user_id'],'123')
        html=header+'<table id="books"><tr class="bookalike review"><td><a class="bookTitle" href="/book/show/1">Example</a><a class="authorName">Author</a></td></tr></table>'
        result=self.post('/goodreads/window',{'url':'https://www.goodreads.com/review/list/123','html':html,'user_id':'123','page':1})
        self.assertEqual(result.json['action'],'complete');self.assertEqual(self.get('/goodreads/state').json['state'],'connected')
        self.assertEqual(self.post('/goodreads/window',{'url':'https://www.goodreads.com/user/sign_in','html':html}).status_code,400)
        self.assertEqual(self.post('/goodreads/window',{'url':'https://www.goodreads.com/','html':header,'user_id':'456'}).status_code,409)

    def test_cover_url_restrictions_and_metadata(self):
        from listen_app.covers import safe_url,mime
        for url in ['http://i.gr-assets.com/x','https://i.gr-assets.com.evil.example/x','https://127.0.0.1/x','https://user@i.gr-assets.com/x','https://i.gr-assets.com:444/x']:
            self.assertEqual(safe_url(url),'')
        self.assertEqual(self.get('/cover?url=https://127.0.0.1/a').status_code,400)
        self.assertEqual(safe_url('https://archive.org/download/arbitrary/file.jpg'),'')
        self.assertEqual(safe_url('https://ia123.us.archive.org/view_archive.php?archive=/private&file=x'),'')
        self.assertTrue(safe_url('https://archive.org/download/l_covers_0008/l_covers_0008_18.zip/0008185004-L.jpg'))
        self.assertIsNone(mime(b'<svg onload="evil"/>'))
        book=parse_book('<h1 id="bookTitle">Test</h1><meta property="og:image" content="https://i.gr-assets.com/a.jpg">','','https://www.goodreads.com/book/show/1')
        self.assertEqual(book['cover'],'https://i.gr-assets.com/a.jpg')
        self.assertIn('_SY600_',safe_url('https://i.gr-assets.com/books/1._SX50_.jpg'))

    def test_neutral_defaults_and_config_validation(self):
        self.assertEqual(settings.load()['languages'],[]);self.assertEqual(settings.load()['excluded_categories'],[])
        for data in [{'theme':'fake'},{'client':{'type':'bad'}},{'client':{'type':'qbittorrent','url':'http://user:secret@example.com'}},{'catalog_host':'127.0.0.1'},{'completed_folder':'relative/path'}]:
            with self.assertRaises(ValueError):settings.validate(data)
    def test_password_stays_in_credential_store(self):
        with patch('keyring.set_password') as save:
            cfg=settings.save({'password':'test-only-password','theme':'dark'})
            save.assert_called_once();self.assertNotIn('test-only-password',(Path(TEMP.name)/'settings.json').read_text());self.assertNotIn('password',cfg)
    def test_filters_use_metadata_not_book_title(self):
        cfg=copy.deepcopy(self.cfg);cfg['languages']=['English','German'];cfg['include_unknown_language']=False;cfg['excluded_categories']=['test-exclusion']
        self.assertTrue(catalog.allowed(self.meta('Deutsch'),cfg));self.assertTrue(catalog.allowed(self.meta('English'),cfg))
        self.assertFalse(catalog.allowed(self.meta('French'),cfg));self.assertFalse(catalog.allowed(self.meta(''),cfg));self.assertFalse(catalog.allowed(self.meta('English',tag='test-exclusion'),cfg))
        cfg['include_unknown_language']=True
        self.assertFalse(catalog.allowed(self.meta('',tag='test-exclusion'),cfg))
        cfg['categories']=['Fiction'];self.assertFalse(catalog.allowed(self.meta('English','Non-fiction'),cfg));self.assertTrue(catalog.allowed(self.meta('English','Fiction'),cfg))
    def test_health_uses_live_metrics(self):
        self.assertEqual(describe({'progress':1,'state':'stalledUP'})['kind'],'complete')
        self.assertEqual(describe({'progress':0,'seeds':2,'availability':1})['kind'],'healthy')
        self.assertEqual(describe({'progress':0,'peers':2})['kind'],'limited')
        self.assertEqual(describe({'progress':0,'state':'metaDL'})['kind'],'checking')
        self.assertEqual(describe({'progress':0})['kind'],'unknown')
        self.assertEqual(describe({'progress':0,'state':'missingFiles'})['kind'],'error')
    def test_qbittorrent_add_stages_and_preserves_folder(self):
        cfg=copy.deepcopy(self.cfg);cfg['client']['url']='http://127.0.0.1:8080'
        with patch.object(clients,'_connect') as connect:
            clients.add('magnet:?xt=urn:btih:'+'a'*40,'../../A book','default',cfg)
            kw=connect.return_value.torrents_add.call_args.kwargs
            self.assertTrue(kw['use_download_path']);self.assertFalse(kw['use_auto_torrent_management']);self.assertEqual(kw['save_path'],str(Path(TEMP.name)/'A book'))
    def test_magnet_handoff_does_not_connect(self):
        cfg=copy.deepcopy(self.cfg);cfg['client']['type']='magnet'
        with patch.object(clients,'_connect') as c:
            result=clients.add('magnet:?xt=urn:btih:'+'a'*40,'Book',config=cfg)
            self.assertTrue(result['handoff']);c.assert_not_called()
    def test_transmission_and_deluge_status_adapters(self):
        cfg=copy.deepcopy(self.cfg);cfg['client']['type']='transmission'
        t=SimpleNamespace(id=1,name='Test',percent_done=.5,status='downloading',total_size=1024,rate_download=25,rate_upload=0,peers_connected=2,download_dir='/downloads')
        c=Mock();c.get_torrents.return_value=[t]
        with patch.object(clients,'_connect',return_value=c):self.assertEqual(clients.torrents(cfg)[0]['progress_percent'],50)
        cfg['client']['type']='deluge';c.get_torrents_status.return_value=SimpleNamespace(result={'hash':{'name':'Test','progress':100,'state':'Seeding','total_size':1024}})
        with patch.object(clients,'_connect',return_value=c):self.assertEqual(clients.torrents(cfg)[0]['health']['kind'],'complete')
    def test_deluge_and_transmission_add_adapters(self):
        cfg=copy.deepcopy(self.cfg);cfg['client']['type']='transmission';cfg['stage_incomplete']=False
        with patch.object(clients,'_connect') as c:
            clients.add('magnet:?xt=urn:btih:'+'a'*40,'Book','default',cfg);c.return_value.add_torrent.assert_called_once()
        cfg['client']['type']='deluge';cfg['stage_incomplete']=True
        with patch.object(clients,'_connect') as c:
            clients.add('magnet:?xt=urn:btih:'+'a'*40,'Book','default',cfg)
            options=c.return_value.add_torrent_magnet.call_args.kwargs['torrent_options'];self.assertTrue(options.move_completed)
    def test_goodreads_book_metadata_and_unauthorized_import(self):
        html='<h1 data-testid="bookTitle">A Book</h1><span class="ContributorLink__name">An Author</span>'
        self.assertEqual(parse_book(html,'','https://www.goodreads.com/book/show/123')['author'],'An Author')
        result=self.post('/goodreads/safari',{'url':'https://evil.example/book/show/123','html':html});self.assertEqual(result.status_code,400)
        self.assertEqual(self.post('/goodreads/safari',{'url':'https://www.goodreads.com/user/sign_in','html':html}).status_code,400)
        result=self.post('/goodreads/safari',{'url':'https://www.goodreads.com/book/show/123','html':html,'mode':'book'});self.assertEqual(result.json['query'],'A Book An Author')
    def test_csv_import_and_safe_render(self):
        response=self.client.post('/goodreads/import',base_url=self.base,headers=self.headers,data={'library':(io.BytesIO(b'Title,Author,Book Id,Exclusive Shelf\n<script>test</script>,Author,123,to-read\n'),'library.csv')},content_type='multipart/form-data')
        self.assertEqual(response.status_code,302)
        with patch.object(clients,'torrents',return_value=[]):
            text=self.get('/discover').get_data(as_text=True);self.assertIn('&lt;script&gt;test&lt;/script&gt;',text)
    def test_search_ranks_title_and_author(self):
        rows=[dict(title='Another book',language='English',format='M4B',file_size='1 MB',bitrate='64kbps',link='https://audiobookbay.lu/a',health={'kind':'unknown','label':'Health unknown','detail':'Unknown'}),dict(title='A Book - An Author',language='English',format='M4B',file_size='1 MB',bitrate='64kbps',link='https://audiobookbay.lu/b',health={'kind':'unknown','label':'Health unknown','detail':'Unknown'})]
        with patch.object(catalog,'search',return_value=rows):
            response=self.client.post('/',base_url=self.base,headers=self.headers,data={'query':'A Book An Author','goodreads_title':'A Book','goodreads_author':'An Author'})
            text=response.get_data(as_text=True);self.assertLess(text.index('A Book - An Author'),text.index('Another book'))
    def test_all_pages_and_connection_error_render(self):
        with patch.object(clients,'torrents',return_value=[]):
            for path in ['/','/discover','/settings','/status','/library']:self.assertEqual(self.get(path).status_code,200,path)
        with patch.object(clients,'torrents',side_effect=clients.ClientError('Unavailable')):self.assertEqual(self.get('/api/torrents').status_code,503)
    def test_catalog_does_not_invent_trackers(self):
        info='b'*40
        soup=BeautifulSoup(f'<div class="post"><div class="postInfo">Category: History Language: English Keywords: Test</div><table><tr><td>Info Hash</td><td>{info}</td></tr></table></div>','html.parser')
        with patch.object(catalog,'fetch',return_value=soup):
            link=catalog.magnet('https://audiobookbay.lu/test',self.cfg);self.assertIn(info,link);self.assertNotIn('&tr=',link)
    def test_explicit_library_move_preserves_managed_torrents(self):
        cfg=copy.deepcopy(self.cfg)
        target=Path(TEMP.name)/'manual-library';target.mkdir(exist_ok=True);cfg['completed_folder']=str(target)
        row={'id':'hash','name':'Book','progress':1,'save_path':str(Path(TEMP.name)/'local'),'content_path':str(Path(TEMP.name)/'local/Book')}
        with patch.object(clients,'torrents',return_value=[row]),patch.object(clients,'_connect') as connect:
            result=clients.move_completed('hash',cfg)
            self.assertTrue(result['moving']);connect.return_value.torrents_set_location.assert_called_once_with(location=str(target),torrent_hashes='hash')
        row['progress']=.5
        with patch.object(clients,'torrents',return_value=[row]),self.assertRaises(clients.ClientError):clients.move_completed('hash',cfg)
    def test_local_orphan_transfer_and_collision_safety(self):
        from listen_app import library
        local=Path(TEMP.name)/'local';cloud=Path(TEMP.name)/'cloud';local.mkdir(exist_ok=True);cloud.mkdir(exist_ok=True)
        item=local/'Test recording.m4b';item.write_text('Synthetic file for transfer testing, not audiobook content.')
        cfg=copy.deepcopy(self.cfg);cfg['downloads_folder']=str(local);cfg['completed_folder']=str(cloud)
        with patch.object(clients,'torrents',return_value=[]):
            result=library.transfer(item.name,cfg);self.assertTrue(result['moved']);self.assertFalse(item.exists());self.assertTrue((cloud/item.name).exists())
            item.write_text('Another synthetic source.')
            with self.assertRaises(clients.ClientError):library.transfer(item.name,cfg)
            self.assertTrue(item.exists())
            with self.assertRaises(clients.ClientError):library.transfer('../outside.m4b',cfg)
        item.unlink();(cloud/item.name).unlink()
    def test_downloads_never_auto_send_to_library(self):
        with self.assertRaises(clients.ClientError):clients.add('magnet:?xt=urn:btih:'+'a'*40,'Book','completed',self.cfg)
    def test_update_check_uses_official_releases(self):
        response=Mock();response.json.return_value=[{'tag_name':'v1.0.0','html_url':'https://github.com/Somamill/listen/releases/tag/v1.0.0','draft':False,'prerelease':False}]
        with patch('requests.get',return_value=response) as fetch:
            result=self.get('/api/update');self.assertTrue(result.json['available']);self.assertEqual(result.json['current'],'0.2.0');self.assertEqual(fetch.call_args.args[0],'https://api.github.com/repos/Somamill/listen/releases')
    def test_bookmarklet_link_never_downloads_automatically(self):
        with patch.object(clients,'add') as add:
            r=self.post('/goodreads/link',{'url':'https://www.goodreads.com/book/show/123','title':'Example','author':'Author'})
            self.assertEqual(r.json['action'],'search');add.assert_not_called()

if __name__=='__main__':unittest.main()
