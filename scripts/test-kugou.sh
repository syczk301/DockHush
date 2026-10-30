#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dockhush-kugou.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
cp Tests/Kugou.swift "$TEST_ROOT/main.swift"
cp Resources/DockHushStrings.json "$TEST_ROOT/"
mkdir -p build/module-cache
xcrun swiftc -module-cache-path build/module-cache "$TEST_ROOT/main.swift" Sources/CloseButton.swift Sources/KugouRuntime.swift Sources/DockCompatibility.swift Sources/Localization.swift -o "$TEST_ROOT/check" -framework AppKit -framework ApplicationServices
"$TEST_ROOT/check" "$TEST_ROOT"
