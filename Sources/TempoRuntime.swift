import AppKit
import CryptoKit

// Launch the unchanged, vendor-signed executable with an external Qt bootstrap.
final class TempoRuntime {
    static let id = "com.edifier.connectHD"
    let root: URL
    private let adapter: URL?
    init(root:URL?=nil,adapter:URL?=nil) {
        self.root=root ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DockHush")
        self.adapter=adapter
    }
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    func hash(_ data: Data) -> String { SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined() }
    func resource() throws -> URL {
        if let adapter=adapter {return adapter}
        guard let url=Bundle.main.url(forResource:"TempoDockPlugin",withExtension:"dylib") else {throw Failure(message:L("tempo.adapterMissing"))}
        return url
    }
    func installedPath() throws -> URL {
        let digest=hash(try Data(contentsOf:resource()))
        return root.appendingPathComponent("TempoRuntime/\(digest)/platforms/TempoDockPlugin.dylib")
    }
    func matchesSession(_ state:[String:Any],pid:Int,launchTime:Double,now:Date=Date()) -> Bool {
        guard state["adapterVersion"] as? Int == 1, state["pid"] as? Int == pid,
              let launch=state["launchTime"] as? Double, abs(launch-launchTime)<0.1,
              let updated=state["updatedAt"] as? Double, abs(now.timeIntervalSince1970-updated)<5,
              let expected=try? installedPath(), state["adapterPath"] as? String == expected.resolvingSymlinksInPath().path,
              let actual=try? Data(contentsOf:expected), let bundled=try? Data(contentsOf:resource()), actual==bundled else {return false}
        return true
    }
    func isInstalled(_ app:NSRunningApplication?) -> Bool {
        guard let app=app, app.bundleIdentifier==Self.id, !app.isTerminated,
              let data=try? Data(contentsOf:root.appendingPathComponent("tempo-session.json")),
              let state=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else {return false}
        return matchesSession(state,pid:Int(app.processIdentifier),launchTime:app.launchDate?.timeIntervalSince1970 ?? 0)
    }
    func prepare(appPath:String) throws -> URL {
        let app=URL(fileURLWithPath:appPath)
        guard let info=try PropertyListSerialization.propertyList(from:Data(contentsOf:app.appendingPathComponent("Contents/Info.plist")),format:nil) as? [String:Any],
              info["CFBundleIdentifier"] as? String == Self.id else {throw Failure(message:L("error.identity"))}
        // Only the tested Qt 6.7 plugin ABI is supported. Updates fail safely.
        let original=app.appendingPathComponent("Contents/Frameworks/PyQt6/Qt6/plugins/platforms/libqcocoa.dylib")
        let originalBytes=try Data(contentsOf:original)
        guard originalBytes.range(of:Data(Array("QTMETADATA !".utf8)+[1,6,7,0])) != nil else {throw Failure(message:L("tempo.qtUnsupported"))}
        let check=Process();check.executableURL=URL(fileURLWithPath:"/usr/bin/codesign")
        check.arguments=["--verify","--deep","--strict","-R", "=anchor apple generic and identifier \"com.edifier.connectHD\" and certificate leaf[subject.OU] = \"H23MN65AK5\"",appPath]
        let pipe=Pipe();check.standardOutput=pipe;check.standardError=pipe
        try check.run();let output=pipe.fileHandleForReading.readDataToEndOfFile();check.waitUntilExit()
        guard check.terminationStatus==0 else {throw Failure(message:L("tempo.signatureInvalid",[String(data:output,encoding:.utf8) ?? ""]))}
        let destination=try installedPath(), bytes=try Data(contentsOf:resource())
        try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        if FileManager.default.fileExists(atPath:destination.path) {
            guard try Data(contentsOf:destination)==bytes else {throw Failure(message:L("error.externalChange"))}
        } else {
            try bytes.write(to:destination,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:destination.path)
        }
        return destination.deletingLastPathComponent()
    }
    func waitForPolicy(hidden:Bool,completion:@escaping(String?)->Void) {
        let deadline=Date().addingTimeInterval(15)
        func poll() {
            let app=NSRunningApplication.runningApplications(withBundleIdentifier:Self.id).first
            if self.isInstalled(app), let app=app, app.activationPolicy == (hidden ? .accessory : .regular) {completion(nil);return}
            if Date()>=deadline {completion(L("tempo.runtimeFailed"));return}
            DispatchQueue.main.asyncAfter(deadline:.now()+0.3,execute:poll)
        }
        poll()
    }
    func launch(appPath:String,plugins:URL,hidden:Bool,completion:@escaping(String?)->Void) {
        let config=NSWorkspace.OpenConfiguration();config.activates=true
        config.environment=["QT_QPA_PLATFORM_PLUGIN_PATH":plugins.path,"QT_QPA_PLATFORMTHEME":"dockhush-tempo"]
        NSWorkspace.shared.openApplication(at:URL(fileURLWithPath:appPath),configuration:config) {_,error in
            DispatchQueue.main.async {
                if let error=error {completion(error.localizedDescription)}
                else {self.waitForPolicy(hidden:hidden,completion:completion)}
            }
        }
    }
}
