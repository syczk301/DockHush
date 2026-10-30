import AppKit
import Darwin

// Launch Services SPI: request an agent launch without editing the signed bundle.
// Resolve both the selector and exported key at runtime; unsupported systems fail closed.
final class KugouRuntime {
    static let id = "com.kugou.mac.Music"
    struct Failure: LocalizedError {
        let message:String
        var errorDescription:String? {message}
    }
    static func supportedInfo(_ info:[String:Any]) -> Bool {
        info["CFBundleIdentifier"] as? String == id &&
        info["CFBundleShortVersionString"] as? String == "20.3.8" &&
        info["CFBundleVersion"] as? String == "3898"
    }
    func configuration(hidden:Bool) throws -> NSWorkspace.OpenConfiguration {
        let config=NSWorkspace.OpenConfiguration()
        let selector=NSSelectorFromString("_setAdditionalLSOpenOptions:")
        let path="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/LaunchServices"
        guard config.responds(to:selector), let library=dlopen(path,RTLD_LAZY) else {throw Failure(message:L("kugou.systemUnsupported"))}
        defer {dlclose(library)}
        let symbol=hidden ? "_kLSOpenOptionUIElementLaunchKey" : "_kLSOpenOptionForegroundLaunchKey"
        guard let address=dlsym(library,symbol), let key=address.assumingMemoryBound(to:CFString?.self).pointee else {throw Failure(message:L("kugou.systemUnsupported"))}
        config.perform(selector,with:[key as String:true] as NSDictionary)
        config.activates=false;config.addsToRecentItems=false
        config.allowsRunningApplicationSubstitution=false
        return config
    }
    func validate(path:String) throws {
        let url=URL(fileURLWithPath:path)
        let info=try PropertyListSerialization.propertyList(from:Data(contentsOf:url.appendingPathComponent("Contents/Info.plist")),format:nil) as? [String:Any] ?? [:]
        guard Self.supportedInfo(info) else {throw Failure(message:L("kugou.versionUnsupported"))}
        let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/codesign")
        process.arguments=["--verify","--deep","--strict","-R","=anchor apple generic and identifier \"com.kugou.mac.Music\" and entitlement[\"com.apple.developer.team-identifier\"] = \"57D9A6W49D\"",path]
        let pipe=Pipe();process.standardOutput=pipe;process.standardError=pipe
        try process.run();_ = pipe.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
        guard process.terminationStatus==0 else {throw Failure(message:L("kugou.signatureInvalid"))}
    }
    func preflight(path:String,hidden:Bool,completion:@escaping(String?)->Void) {
        do {_ = try configuration(hidden:hidden)} catch {completion(error.localizedDescription);return}
        DispatchQueue.global(qos:.userInitiated).async {
            let result=Result {try self.validate(path:path)}
            DispatchQueue.main.async {
                if case .failure(let error)=result {completion(error.localizedDescription)} else {completion(nil)}
            }
        }
    }
    func quit(completion:@escaping(Bool)->Void) {
        let apps=NSRunningApplication.runningApplications(withBundleIdentifier:Self.id).filter{!$0.isTerminated}
        for app in apps {_ = app.terminate()}
        let deadline=Date().addingTimeInterval(45)
        func poll() {
            if apps.allSatisfy({$0.isTerminated}) {completion(true)}
            else if Date()>=deadline {completion(false)}
            else {DispatchQueue.main.asyncAfter(deadline:.now()+0.4,execute:poll)}
        }
        poll()
    }
    func apply(path:String,hidden:Bool,completion:@escaping(String?,Bool)->Void) {
        // Validate again immediately before launch, including after a normal quit.
        preflight(path:path,hidden:hidden) {error in
            if let error=error {completion(error,false);return}
            let current=NSRunningApplication.runningApplications(withBundleIdentifier:Self.id).filter{!$0.isTerminated}
            let target=URL(fileURLWithPath:path).resolvingSymlinksInPath()
            guard !current.contains(where:{$0.bundleURL?.resolvingSymlinksInPath() != target}),
                  !hidden || current.isEmpty else {completion(L("kugou.launchConflict"),false);return}
            do {
                let config=try self.configuration(hidden:hidden)
                NSWorkspace.shared.openApplication(at:target,configuration:config) {app,error in
                    DispatchQueue.main.async {
                        guard let app=app,error==nil else {completion(error?.localizedDescription ?? L("error.notLaunched"),true);return}
                        let start=Date(),deadline=Date().addingTimeInterval(12)
                        var matchingSince:Date?
                        func poll() {
                            guard !app.isTerminated,app.bundleIdentifier==Self.id,app.bundleURL?.resolvingSymlinksInPath()==target else {completion(L("error.exited"),true);return}
                            if app.activationPolicy == (hidden ? .accessory : .regular) {
                                if matchingSince==nil {matchingSince=Date()}
                                if Date().timeIntervalSince(matchingSince!)>=2 && Date().timeIntervalSince(start)>=3 {completion(nil,true);return}
                            } else {matchingSince=nil}
                            if Date()>=deadline {completion(L("kugou.policyFailed"),true);return}
                            DispatchQueue.main.asyncAfter(deadline:.now()+0.25,execute:poll)
                        }
                        poll()
                    }
                }
            } catch {completion(error.localizedDescription,false)}
        }
    }
}
