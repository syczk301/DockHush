from pathlib import Path
from html.parser import HTMLParser
import shutil
root = Path(__file__).resolve().parent
class Audit(HTMLParser):
    def __init__(self):
        super().__init__(); self.ids=[]; self.links=[]; self.assets=[]; self.headings=0
    def handle_starttag(self, tag, attrs):
        a=dict(attrs)
        if 'id' in a: self.ids.append(a['id'])
        if tag=='h1': self.headings+=1
        if tag=='a': self.links.append(a.get('href',''))
        if tag in ('img','script'): self.assets.append(a.get('src',''))
        if tag=='link' and a.get('rel') in ('stylesheet','icon'): self.assets.append(a.get('href',''))
page=(root/'index.html').read_text(); audit=Audit(); audit.feed(page)
assert audit.headings==1, 'Exactly one h1 required'
assert len(audit.ids)==len(set(audit.ids)), 'Duplicate element IDs'
assert 'chatgpt.site' not in page, 'Old hosting link remains'
for href in audit.links:
    assert href, 'Empty link'
    if href.startswith('#') and href!='#': assert href[1:] in audit.ids, href
for asset in audit.assets:
    if not asset.startswith('https://'): assert (root/asset).is_file(), asset
out=root.parent/'_site'
if out.exists(): shutil.rmtree(out)
out.mkdir()
for name in ('index.html','style.css','app.js','robots.txt','sitemap.xml','assets'):
    p=root/name
    if p.is_dir(): shutil.copytree(p,out/name)
    else: shutil.copy2(p,out/name)
(out/'.nojekyll').touch()
print('Static website validated and built into _site/')
