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

Download `DockHush-0.2.0-universal.dmg` from [Releases](https://github.com/syczk301/DockHush/releases), drag the app into Applications, eject the image, and launch the installed app.

The build targets **macOS 13+, Apple Silicon and Intel**. Runtime testing was performed on Apple Silicon / macOS 26. Intel and older macOS versions are cross-compiled targets, not yet tested on hardware.

The DMG is **ad-hoc signed, without Apple Developer ID signing or notarization**. macOS may block first launch. After verifying the download source, review it yourself in System Settings → Privacy & Security, or build from source. Do not disable Gatekeeper or SIP. Rebuilt or updated binaries may need their existing permission entries removed and added again.

Grant **Accessibility** for Hide on Close and, if needed, **App Management** for editing some third-party app settings. Both are system-level permissions. No third-party apps are enabled by default. Add the installed app to macOS Login Items if you want it to start when you log in.

The gear button opens language and permission settings plus the backup folder. Right-click a row to open an app or hide its windows. View Details shows the full operation result.

## Compatibility and recovery

Hide on Close normally hides the whole app, including multiple windows. Generic interception requires an accessible close button. Custom window controls may not work. TempoHub has a coordinate-based adapter that can break after UI changes.

For ordinary apps, Dock controls edit `Contents/Info.plist` → `LSUIElement` and restart the target app. **Editing a signed app bundle can invalidate its original signature.** DockHush never re-signs third-party apps. Protected system apps, non-writable configurations, and symlinked configurations are excluded. Save work first: a quit timeout cancels the change without forcibly terminating ordinary apps.

A check verifies process survival and the resulting activation policy. Apps may later override their Dock state. Failed changes restore the previous file and attempt to reopen apps that were running. Interrupted transactions are examined on the next launch. App updates or conflicting edits stop automatic restoration rather than overwriting newer files; use View Details to locate the backup.

### TempoHub runtime integration

Verified with TempoHub 1.3.0 / Qt 6.7 on Apple Silicon: an optional external Qt extension changes Dock state inside the process without modifying Info.plist, executables, or the vendor signature, and without opening a debugger. First use requires a confirmed quit and relaunch through DockHush; later show/hide changes apply directly. Hide on Close remains an independent Accessibility integration. After fully quitting TempoHub, reopen it through DockHush to load the adapter again. Normal Finder launches always use the original vendor app.

Setup validates the vendor signature and Qt plugin version. Unsupported updates stop safely; failed integration attempts a normal-launch fallback. Legacy configuration edits and backup replay remain blocked. Adapter copies and state are stored under `~/Library/Application Support/DockHush/TempoRuntime/` and `tempo-session.json`.

### Kugou Music

Kugou Music 20.3.8 (Mac Catalyst) can omit the close-button subrole during accessibility hit testing. The adapter compares the hit button with the same process’s published window close button, using its exact position and size. Only a matching close button hides the app; minimize, zoom and content buttons retain their normal behavior. Accessibility permission is required.

Verified with a physical mouse click on Kugou 20.3.8 / Apple Silicon / macOS 26: the red close button hides the app with the same PID alive and zero visible windows; opening it through DockHush restores the window in the same process; Command-Q exits normally. Audio playback continuity, Intel hardware and other Kugou versions have not been verified. A rebuilt app may require removing its old Accessibility entry and adding the current app again.

Dock control uses the Launch Services UIElement launch option without modifying Kugou or its vendor signature. Hiding requires confirmation to quit and reopen normally, interrupting playback; showing can take effect in the same process. Close-to-hide remains independent. Use DockHush's Open Application action to restore a hidden window: Finder, the Dock or other launchers may cause Kugou to show its icon again. After a full quit, launch through DockHush to apply the saved hidden setting.

Only Kugou 20.3.8 (3898) is currently allowed, with vendor signature validation before use. This adapter uses a private macOS launch interface that may stop working after system updates. Missing interfaces, unsupported versions, another running copy or a quit timeout stop the operation. Dock state is checked after launch; failures attempt ordinary opening and never replay old configuration backups.

### Optional ZSpace integration

The adapter expects `/Applications/极空间.app` and **Node.js 22+**, found in standard Homebrew locations or process PATH. Other features do not require Node.js.

Toggle either switch in the ZSpace row to start integration. Save your work before accepting the first-use prompt; after confirmation, DockHush gracefully quits and relaunches ZSpace: a temporary `127.0.0.1` debugger installs close/Dock handlers inside the main process, then closes and checks the port. Local debugger connections can access process data while it is open. Support depends on the client version; setup failure may terminate the newly started process to avoid leaving its debugger enabled. If ZSpace does not quit in time, setup stops and settings remain unapplied. After integration, both switches apply within about one second. Integration must be installed again after ZSpace exits.

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

Outputs: `build/DockHush.app`, `dist/DockHush-0.2.0-universal.dmg` and its SHA-256 checksum. Both arm64 and x86_64 are built and merged. The default version comes from the root `VERSION` file. Override `VERSION` consistently for building and packaging; packaging checks the app version. `SIGN_IDENTITY` can select your own Developer ID identity; notarization is a separate step.

`./scripts/test-recovery.sh` creates and launches isolated test apps under `build/` to check hide/show, rollback, interrupted recovery and external edit conflicts. It needs a logged-in macOS GUI session and does not alter installed third-party apps.

Contributions are welcome. Include macOS, CPU, app versions and reproduction steps in reports. Do not share unreviewed logs, backups, app lists or private paths. Report security issues through the repository’s private vulnerability reporting feature.

[MIT licensed](LICENSE). Third-party names identify supported integrations only; no affiliation or endorsement is implied.
