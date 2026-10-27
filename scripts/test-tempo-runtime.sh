#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dockhush-tempo-runtime-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
cp Tests/TempoRuntime.swift "$TEST_ROOT/main.swift"
cp Resources/DockHushStrings.json "$TEST_ROOT/"
xcrun swiftc -module-cache-path build/module-cache "$TEST_ROOT/main.swift" Sources/TempoRuntime.swift Sources/Localization.swift -o "$TEST_ROOT/check" -framework AppKit
if [ "$#" -gt 0 ]; then
  "$TEST_ROOT/check" "$TEST_ROOT" "$1"
else
  "$TEST_ROOT/check" "$TEST_ROOT"
fi
