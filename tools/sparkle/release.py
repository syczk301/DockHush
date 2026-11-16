#!/usr/bin/env python3
"""Generate a signed update archive/feed locally; does not publish."""
from pathlib import Path
import json,subprocess,sys,plistlib
root=Path(__file__).resolve().parent;cfg=json.loads((root/'config.json').read_text())
if len(sys.argv)!=3:raise SystemExit('Usage: release.py APP_BUNDLE OUTPUT_DIRECTORY')
app=Path(sys.argv[1]).resolve();out=Path(sys.argv[2]).resolve();out.mkdir(parents=True,exist_ok=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['SUPublicEDKey']==cfg['publicKey'] and info['SUFeedURL']==cfg['feedURL']
archive=out/(cfg['app']+'-'+info['CFBundleShortVersionString']+'.zip')
subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(app),str(archive)],check=True)
subprocess.run([str(root/'vendor/bin/generate_appcast'),'--account',cfg['account'],'--download-url-prefix',cfg['downloadURLPrefix'],'--maximum-deltas','0',str(out)],check=True)
print('Signed update prepared:',archive)
