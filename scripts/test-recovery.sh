#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
TEST_ROOT="$(mktemp -d "$PWD/build/recovery.XXXXXX")"
python3 - "$TEST_ROOT" <<'PY'
import pathlib,plistlib,sys,subprocess
root=pathlib.Path(sys.argv[1])
for kind in ['Native','Override','Exit']:
    app=root/(kind+'DockProbe.app');(app/'Contents/MacOS').mkdir(parents=True)
    info={'CFBundleIdentifier':'io.github.syczk301.DockHush.test.'+kind.lower(),'CFBundleName':kind+'DockProbe','CFBundleExecutable':'Probe','CFBundlePackageType':'APPL','LSUIElement':False}
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    source=pathlib.Path('Tests/Probe.swift').read_text()
    if kind=='Override':source=source.replace('window=NSWindow(', 'NSApp.setActivationPolicy(.regular)\n        window=NSWindow(')
    if kind=='Exit':source='import Foundation\nexit(42)\n'
    f=root/(kind+'.swift');f.write_text(source)
    subprocess.run(['xcrun','swiftc','-module-cache-path','build/module-cache',str(f),'-o',str(app/'Contents/MacOS/Probe'),'-framework','AppKit'],check=True)
PY
cp Resources/DockHushStrings.json "$TEST_ROOT/"
for test in Compatibility Recovery; do
  cp "Tests/$test.swift" "$TEST_ROOT/main.swift"
  xcrun swiftc -module-cache-path build/module-cache "$TEST_ROOT/main.swift" Sources/DockCompatibility.swift Sources/Localization.swift -o "$TEST_ROOT/$test" -framework AppKit
  "$TEST_ROOT/$test" "$TEST_ROOT"
done
printf 'Isolated test results retained at: %s\n' "$TEST_ROOT"
