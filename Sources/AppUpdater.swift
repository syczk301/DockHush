import AppKit
import Sparkle

/// One retained updater per app. Uses this app's HTTPS feed and Ed25519 public key.
@MainActor
final class AppUpdater: NSObject, NSMenuItemValidation {
    static let shared = AppUpdater()
    private var controller: SPUStandardUpdaterController?
    func start() {
        guard controller == nil else { return }
        guard !CommandLine.arguments.contains(where: { $0.hasSuffix("-test") }) else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    @objc func checkForUpdates(_ sender: Any? = nil) {
        start()
        controller?.checkForUpdates(sender)
    }
    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        item.target = self
        return item
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        controller?.updater.canCheckForUpdates ?? false
    }
}
