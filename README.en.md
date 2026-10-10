# DockHush · 隐坞

**Keep apps running. Keep your desktop clear.**

[简体中文](README.md) · [Download DMG](https://github.com/syczk301/DockHush/releases/latest) · [MIT License](LICENSE)

A native SwiftUI/AppKit menu bar utility for macOS. Control app closing behavior and Dock visibility independently. No account or telemetry.

## Features

- Scan installed and running apps; search, filter, and optionally hide system apps from the list.
- **Hide on Close** hides supported apps when their red close button is clicked. ⌘Q still quits them.
- **Show in Dock**: on shows the icon, off hides it. DockHush itself appears in the same list.
- Instant **System Default / 简体中文 / English** switching for the window, menus and messages.
- Back up Dock configuration before changing it; restore failed changes and avoid overwriting conflicting edits.

## Install

Download `DockHush-0.1.0-universal.dmg` from [Releases](https://github.com/syczk301/DockHush/releases), drag the app into Applications, eject the image, and launch the installed app.

The build targets **macOS 13+, Apple Silicon and Intel**. Runtime testing was performed on Apple Silicon / macOS 26. Intel and older macOS versions are cross-compiled targets, not yet tested on hardware.

The DMG is **ad-hoc signed, without Apple Developer ID signing or notarization**. macOS may block first launch. After verifying the download source, review it yourself in System Settings → Privacy & Security, or build from source. Do not disable Gatekeeper or SIP. Rebuilt or updated binaries may need their existing permission entries removed and added again.

Grant **Accessibility** for Hide on Close and, if needed, **App Management** for editing some third-party app settings. Both are system-level permissions. No third-party apps are enabled by default. Add the installed app to macOS Login Items if you want it to start when you log in.

The gear button opens language and permission settings plus the backup folder. Right-click a row to open an app or hide its windows. View Details shows the full operation result.

## Compatibility and recovery

Hide on Close normally hides the whole app, including multiple windows. Generic interception requires an accessible close button. Custom window controls may not work. TempoHub has a coordinate-based adapter that can break after UI changes.

For ordinary apps, Dock controls edit `Contents/Info.plist` → `LSUIElement` and restart the target app. **Editing a signed app bundle can invalidate its original signature.** DockHush never re-signs third-party apps. Protected system apps, non-writable configurations, and symlinked configurations are excluded. Save work first: a quit timeout cancels the change without forcibly terminating ordinary apps.

A check verifies process survival and the resulting activation policy. Apps may later override their Dock state. Failed changes restore the previous file and attempt to reopen apps that were running. Interrupted transactions are examined on the next launch. App updates or conflicting edits stop automatic restoration rather than overwriting newer files; use View Details to locate the backup.

### Optional ZSpace integration

The adapter expects `/Applications/极空间.app` and **Node.js 22+**, found in standard Homebrew locations or process PATH. Other features do not require Node.js.

Save work and quit ZSpace, configure its row, then choose Open App. A separate prompt explains and requests activation: a temporary `127.0.0.1` debugger installs close/Dock handlers inside the main process, then closes and checks the port. Local debugger connections can access process data while it is open. Support depends on the client version; setup failure may terminate the newly started process to avoid leaving its debugger enabled. An already-running unhooked instance is not restarted automatically.

## Local data and uninstalling

- Preferences: `io.github.syczk301.DockHush`
- Rules and backups: `~/Library/Application Support/DockHush/`
- ZSpace diagnostic log: `~/Library/Logs/DockHush/zspace.log`

Quitting DockHush stops generic close interception but does not undo persisted Dock edits. ZSpace runtime handlers remain until ZSpace quits. Restore desired Dock states and quit ZSpace before uninstalling. The public app uses separate settings from the earlier private helper; do not run both simultaneously.

## Build and test

Requires macOS, Xcode Command Line Tools (`xcode-select --install`), Python 3 and a Swift compiler/SDK supporting macOS 13.

```sh
git clone https://github.com/syczk301/DockHush.git
cd DockHush
./scripts/check.sh
./scripts/build.sh
./scripts/package-dmg.sh
```

Outputs: `build/DockHush.app`, `dist/DockHush-0.1.0-universal.dmg` and its SHA-256 checksum. Both arm64 and x86_64 are built and merged. Override `VERSION` as needed. `SIGN_IDENTITY` can select your own Developer ID identity; notarization is a separate step.

`./scripts/test-recovery.sh` creates and launches isolated test apps under `build/` to check hide/show, rollback, interrupted recovery and external edit conflicts. It needs a logged-in macOS GUI session and does not alter installed third-party apps.

Contributions are welcome. Include macOS, CPU, app versions and reproduction steps in reports. Do not share unreviewed logs, backups, app lists or private paths. Report security issues through the repository’s private vulnerability reporting feature.

[MIT licensed](LICENSE). Third-party names identify supported integrations only; no affiliation or endorsement is implied.
