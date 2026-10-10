#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json,re,pathlib
root=pathlib.Path('.')
catalog=json.loads((root/'Resources/DockHushStrings.json').read_text())
for key,values in catalog.items():
    assert set(values)=={'en','zh-Hans'},key
    assert all(values.values()),key
    assert sorted(re.findall(r'\{\d+\}',values['en']))==sorted(re.findall(r'\{\d+\}',values['zh-Hans'])),key
for file in (root/'Sources').glob('*.swift'):
    for key in re.findall(r'L\("([^"]+)"',file.read_text()):
        assert key in catalog or key=='filter.',(file,key)
print(f'{len(catalog)} translation keys checked')
PY
mkdir -p build/localization-test build/module-cache
cp Tests/Localization.swift build/localization-test/main.swift
cp Resources/DockHushStrings.json build/localization-test/
xcrun swiftc -module-cache-path build/module-cache build/localization-test/main.swift Sources/Localization.swift -o build/localization-test/check -framework AppKit
build/localization-test/check
if command -v node >/dev/null; then
  node --check Resources/zspace-switch-launch.mjs
  node --check Resources/zspace-switch-hook.js
else
  echo 'Node.js unavailable: optional ZSpace syntax checks skipped.'
fi
