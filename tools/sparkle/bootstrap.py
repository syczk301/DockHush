#!/usr/bin/env python3
"""Pinned official Sparkle distribution. Preserve upstream signatures and symlinks."""
from pathlib import Path
import hashlib,json,subprocess,sys,plistlib,os,shutil
root=Path(__file__).resolve().parent
config=json.loads((root/'config.json').read_text())
vendor=root/'vendor'; framework=vendor/'Sparkle.framework'
if not framework.exists():
    vendor.mkdir(exist_ok=True)
    archive=vendor/'Sparkle-2.10.1.tar.xz'
    subprocess.run(['curl','-fL','--retry','2','https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz','-o',str(archive)],check=True)
    assert hashlib.sha256(archive.read_bytes()).hexdigest()=='1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27','Sparkle download hash mismatch'
    subprocess.run(['tar','-xf',str(archive),'-C',str(vendor)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(framework)],check=True)
if len(sys.argv)>1:
    app=Path(sys.argv[1]);dest=app/'Contents/Frameworks/Sparkle.framework'
    dest.parent.mkdir(parents=True,exist_ok=True)
    subprocess.run(['ditto',str(framework),str(dest)],check=True)
    shutil.copy2(vendor/'LICENSE', app/'Contents/Resources/Sparkle-LICENSE.txt')
    path=app/'Contents/Info.plist';info=plistlib.loads(path.read_bytes())
    info.update(SUFeedURL=config['feedURL'],SUPublicEDKey=config['publicKey'],SUEnableAutomaticChecks=True,SUAutomaticallyUpdate=False,SUAllowsAutomaticUpdates=True,SUVerifyUpdateBeforeExtraction=True,SURequireSignedFeed=True)
    path.write_bytes(plistlib.dumps(info))
    # Developer ID release builds must re-sign nested code with the host identity.
    identity=os.environ.get('SIGN_IDENTITY','-')
    if identity!='-':
        for node in sorted(dest.rglob('*'),key=lambda p:len(p.parts),reverse=True):
            if node.is_symlink():continue
            if node.suffix in ['.xpc','.app'] or (node.is_file() and node.name in ['Autoupdate','Sparkle']):
                subprocess.run(['codesign','--force','--options','runtime','--timestamp','--sign',identity,str(node)],check=True)
        subprocess.run(['codesign','--force','--options','runtime','--timestamp','--sign',identity,str(dest)],check=True)
