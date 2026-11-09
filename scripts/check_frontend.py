"""Validate rendered frontend scripts without using personal app data. Requires Node.js."""
import os,tempfile,subprocess,sys
ROOT=__import__("pathlib").Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
os.chdir(ROOT)
from pathlib import Path
from bs4 import BeautifulSoup
with tempfile.TemporaryDirectory() as d:
 os.environ['LISTEN_DATA_DIR']=d
 from listen_app.server import create_app
 app=create_app();app.config['BOUND_PORT']=58432;c=app.test_client();headers={'X-Listen-Token':app.config['SERVICE_TOKEN']};base='http://127.0.0.1:58432'
 total=0
 for page in ['/','/discover','/settings','/status','/library']:
  r=c.get(page,base_url=base,headers=headers);assert r.status_code==200,page
  soup=BeautifulSoup(r.data,'html.parser')
  for i,script in enumerate(soup.select('script:not([src])')):
   p=Path(d)/('script'+str(total)+'.js');p.write_text(script.get_text());subprocess.run(['node','--check',str(p)],check=True,capture_output=True);total+=1
 print('Rendered pages: 5; inline JavaScript syntax checks:',total)
 for source in Path('listen_app/static/js').glob('*.js'):subprocess.run(['node','--check',str(source)],check=True,capture_output=True)
print('Standalone JavaScript syntax: PASS')
