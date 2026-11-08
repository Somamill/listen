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
            clients.add('magnet:?xt=urn:btih:'+'a'*40,'../../A book','completed',cfg)
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
            clients.add('magnet:?xt=urn:btih:'+'a'*40,'Book','completed',cfg);c.return_value.add_torrent.assert_called_once()
        cfg['client']['type']='deluge';cfg['stage_incomplete']=True
        with patch.object(clients,'_connect') as c:
            clients.add('magnet:?xt=urn:btih:'+'a'*40,'Book','completed',cfg)
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
            for path in ['/','/discover','/settings','/status']:self.assertEqual(self.get(path).status_code,200,path)
        with patch.object(clients,'torrents',side_effect=clients.ClientError('Unavailable')):self.assertEqual(self.get('/api/torrents').status_code,503)
    def test_catalog_does_not_invent_trackers(self):
        info='b'*40
        soup=BeautifulSoup(f'<div class="post"><div class="postInfo">Category: History Language: English Keywords: Test</div><table><tr><td>Info Hash</td><td>{info}</td></tr></table></div>','html.parser')
        with patch.object(catalog,'fetch',return_value=soup):
            link=catalog.magnet('https://audiobookbay.lu/test',self.cfg);self.assertIn(info,link);self.assertNotIn('&tr=',link)
    def test_bookmarklet_link_never_downloads_automatically(self):
        with patch.object(clients,'add') as add:
            r=self.post('/goodreads/link',{'url':'https://www.goodreads.com/book/show/123','title':'Example','author':'Author'})
            self.assertEqual(r.json['action'],'search');add.assert_not_called()

if __name__=='__main__':unittest.main()
