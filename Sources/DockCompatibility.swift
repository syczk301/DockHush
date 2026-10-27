import AppKit
import CryptoKit

// Only Info.plist is changed. Vendor executables, signatures and entitlements stay intact.
final class DockCompatibility {
    struct Record: Codable {
        var id: String
        var path: String
        var executable: String
        var executableHash: String
        var baseline: Data
        var before: Data
        var target: Data
        var hidden: Bool
        var wasRunning: Bool
        var phase: String
        var date: Date
    }
    let root: URL
    var active: [String: Record] = [:]
    var pending: [(URL, Record)] = []
    var busy = false
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DockHush/Compatibility")
        let urls = (try? FileManager.default.contentsOfDirectory(at: self.root, includingPropertiesForKeys: nil)) ?? []
        let records = urls.compactMap { dir -> (URL,Record)? in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("transaction.json")), let record = try? JSONDecoder().decode(Record.self, from: data) else {return nil}
            return (dir,record)
        }.sorted {$0.1.date < $1.1.date}
        for (dir, record) in records {
            if record.phase == "committed" {active[record.id] = record}
            if ["prepared", "applied", "verifying", "restoring", "conflict"].contains(record.phase) {pending.append((dir,record))}
        }
    }
    func plist(_ path: String) -> URL { URL(fileURLWithPath:path).appendingPathComponent("Contents/Info.plist") }
    func hash(_ path: String) throws -> String {
        let file = try FileHandle(forReadingFrom: URL(fileURLWithPath:path)); defer {try? file.close()}
        var digest = SHA256()
        while let data = try file.read(upToCount: 1024*1024), !data.isEmpty {digest.update(data:data)}
        return digest.finalize().map {String(format:"%02x",$0)}.joined()
    }
    func reason(_ path: String) -> String? {
        let url = plist(path)
        if let data = try? Data(contentsOf:url),
           let info = try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any],
           info["CFBundleIdentifier"] as? String == "com.edifier.connectHD" {
            return L("tempo.dockUnsupported")
        }
        let resolved = URL(fileURLWithPath:path).resolvingSymlinksInPath().path
        if resolved.hasPrefix("/System/") || resolved.hasPrefix("/Library/Apple/") {return L("error.protected")}
        if (try? url.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) == true {return L("error.symlink")}
        if !FileManager.default.isWritableFile(atPath:url.path) {return L("error.noWrite")}
        if pending.contains(where:{$0.1.path == path}) {return L("error.pending")}
        return nil
    }
    func save(_ record: Record, _ dir: URL) throws {
        try JSONEncoder().encode(record).write(to:dir.appendingPathComponent("transaction.json"), options:.atomic)
    }
    func write(_ data: Data, to url: URL, expecting expected: Data) throws {
        guard try Data(contentsOf:url) == expected else {throw Failure(L("error.externalChange"))}
        // In-place write preserves the existing file owner, mode, ACL and extended attributes.
        let file = try FileHandle(forWritingTo:url); defer {try? file.close()}
        try file.seek(toOffset:0); try file.write(contentsOf:data); try file.truncate(atOffset:UInt64(data.count)); try file.synchronize()
    }
    struct Failure: LocalizedError {let message:String;init(_ message:String){self.message=message};var errorDescription:String?{message}}
    func instances(_ id:String) -> [NSRunningApplication] {NSRunningApplication.runningApplications(withBundleIdentifier:id).filter{!$0.isTerminated}}
    func quit(_ id:String, completion:@escaping(Bool)->Void) {
        let apps = instances(id)
        for app in apps { _ = app.terminate() }
        let deadline = Date().addingTimeInterval(20)
        func poll() {
            if self.instances(id).isEmpty {completion(true)}
            else if Date() >= deadline {completion(false)}
            else {DispatchQueue.main.asyncAfter(deadline:.now()+0.4, execute:poll)}
        }
        poll()
    }
    func launch(_ record:Record, verify:Bool, completion:@escaping(String?)->Void) {
        let config = NSWorkspace.OpenConfiguration(); config.activates = false
        var done = false
        func finish(_ error:String?) {if !done {done=true;completion(error)}}
        DispatchQueue.main.asyncAfter(deadline:.now()+20) {finish(L("error.launchTimeout"))}
        NSWorkspace.shared.openApplication(at:URL(fileURLWithPath:record.path),configuration:config) { app,error in
            DispatchQueue.main.async {
                guard !done else {return}
                guard error == nil, let app = app else {finish(error?.localizedDescription ?? L("error.notLaunched"));return}
                let deadline = Date().addingTimeInterval(6)
                func poll() {
                    guard !done else {return}
                    if app.isTerminated {finish(L("error.exited"));return}
                    if Date() >= deadline {
                        if verify && ((app.activationPolicy != .regular) != record.hidden) {finish(L("error.unsupported"))}
                        else {finish(nil)}
                    } else {DispatchQueue.main.asyncAfter(deadline:.now()+0.5,execute:poll)}
                }
                poll()
            }
        }
    }
    func apply(id:String, path:String, hidden:Bool, progress:@escaping(String)->Void, completion:@escaping(Bool,String)->Void) {
        guard !busy else {completion(false,L("error.busy"));return}
        // TempoHub's vendor signature seals Info.plist. Never patch or replay it.
        guard id != "com.edifier.connectHD" else {completion(false,L("tempo.dockUnsupported"));return}
        if let why = reason(path) {completion(false,why);return}
        if instances(id).contains(where:{$0.bundleURL?.resolvingSymlinksInPath() != URL(fileURLWithPath:path).resolvingSymlinksInPath()}) {
            completion(false,L("error.otherCopy"));return
        }
        busy = true
        let dir = root.appendingPathComponent(UUID().uuidString)
        var record: Record
        do {
            let data = try Data(contentsOf:plist(path))
            guard let info = try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any], info["CFBundleIdentifier"] as? String == id,
                  let executable = info["CFBundleExecutable"] as? String, !executable.contains("/") else {throw Failure(L("error.identity"))}
            let execPath = URL(fileURLWithPath:path).appendingPathComponent("Contents/MacOS").appendingPathComponent(executable).path
            let fingerprint = try hash(execPath)
            let old = active[id]
            if let old = old, old.path == path, (old.target != data || old.executableHash != fingerprint) {throw Failure(L("error.updatedConfig"))}
            let baseline = old?.baseline ?? data
            var baselineInfo = try PropertyListSerialization.propertyList(from:baseline,format:nil) as! [String:Any]
            let originalHidden = (baselineInfo["LSUIElement"] as? NSNumber)?.boolValue ?? (baselineInfo["LSUIElement"] as? String).map{["1","true","YES"].contains($0)} ?? false
            let target: Data
            if hidden == originalHidden {target = baseline}
            else {baselineInfo["LSUIElement"] = hidden;target = try PropertyListSerialization.data(fromPropertyList:baselineInfo,format:.xml,options:0)}
            record = Record(id:id,path:path,executable:execPath,executableHash:fingerprint,baseline:baseline,before:data,target:target,hidden:hidden,wasRunning:!instances(id).isEmpty,phase:"prepared",date:Date())
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try FileManager.default.copyItem(at:plist(path),to:dir.appendingPathComponent("Info.plist.backup"))
            try save(record,dir)
        } catch {busy=false;completion(false,error.localizedDescription);return}
        progress(L("progress.quitting"))
        quit(id) { stopped in
            guard stopped else {
                record.phase="cancelled";try? self.save(record,dir);self.busy=false
                completion(false,L("error.quitTimeout"));return
            }
            do {
                guard try self.hash(record.executable) == record.executableHash else {throw Failure(L("error.updatedStop"))}
                try self.write(record.target,to:self.plist(path),expecting:record.before)
                record.phase="verifying";try self.save(record,dir)
                progress(L("progress.verifying"))
                self.launch(record,verify:true) { error in
                    if let error = error {
                        progress(L("progress.restoring"))
                        self.restore(record,dir:dir) { restored,message in
                            self.busy=false;completion(false,L("result.details",[error,message]))
                        }
                    } else {
                        do {
                            record.phase="committed";try self.save(record,dir);self.active[id]=record;self.busy=false
                            completion(true,hidden ? L("result.hidden") : L("result.shown"))
                        } catch {
                            self.restore(record,dir:dir) { _,message in self.busy=false;completion(false,L("error.saveResult", [String(describing: message)])) }
                        }
                    }
                }
            } catch {
                self.restore(record,dir:dir) { _,message in self.busy=false;completion(false,L("result.details",[error.localizedDescription,message])) }
            }
        }
    }
    func restore(_ input:Record, dir:URL, completion:@escaping(Bool,String)->Void) {
        var record=input
        func conflict(_ message:String) {
            record.phase="conflict";try? self.save(record,dir)
            self.pending.removeAll{$0.0==dir}; self.pending.append((dir,record))
            completion(false,L("result.backup",[message,dir.path]))
        }
        guard record.id != "com.edifier.connectHD" else {conflict(L("tempo.dockUnsupported"));return}
        do {
            guard !instances(record.id).contains(where:{$0.bundleURL?.resolvingSymlinksInPath() != URL(fileURLWithPath:record.path).resolvingSymlinksInPath()}) else {conflict(L("error.pathChanged"));return}
            let current=try Data(contentsOf:plist(record.path))
            guard try hash(record.executable)==record.executableHash, current==record.target || current==record.before else {conflict(L("error.restoreConflict"));return}
            record.phase="restoring";try save(record,dir)
        } catch {conflict(L("error.readRecovery", [String(describing: error.localizedDescription)]));return}
        quit(record.id) { stopped in
            guard stopped else {conflict(L("error.restoreQuit"));return}
            do {
                guard try self.hash(record.executable)==record.executableHash else {throw Failure(L("error.updated"))}
                let current=try Data(contentsOf:self.plist(record.path))
                if current != record.before {try self.write(record.before,to:self.plist(record.path),expecting:record.target)}
                guard try Data(contentsOf:self.plist(record.path))==record.before else {throw Failure(L("error.restoreVerify"))}
                record.phase="rolledBack";try self.save(record,dir);self.pending.removeAll{$0.0==dir}
                if record.wasRunning {
                    self.launch(record,verify:false) {error in
                        completion(true,error == nil ? L("result.restoredOpened") : L("error.reopen", [String(describing: error!)]))
                    }
                } else {completion(true,L("result.restored"))}
            } catch {conflict(L("error.restore", [String(describing: error.localizedDescription)]))}
        }
    }
    func recover(progress:@escaping(String)->Void) {
        guard !busy, let (dir,record)=pending.first(where:{$0.1.phase != "conflict"}) else {return}
        busy=true;progress(L("progress.recovering"))
        restore(record,dir:dir) {_,message in self.busy=false;progress(message);self.recover(progress:progress)}
    }
}
