#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dockhush-tempo-safety.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
cp Tests/TempoSafety.swift "$TEST_ROOT/main.swift"
cp Resources/DockHushStrings.json "$TEST_ROOT/"
xcrun swiftc -module-cache-path "$TEST_ROOT/cache" "$TEST_ROOT/main.swift" Sources/DockCompatibility.swift Sources/Localization.swift -o "$TEST_ROOT/check" -framework AppKit
"$TEST_ROOT/check" "$TEST_ROOT"
