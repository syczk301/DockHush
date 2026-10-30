import AppKit
import SwiftUI
import ApplicationServices

let tempoID = "com.edifier.connectHD"
let zspaceID = "com.zentraedi.zspaceMacApp"
let helperID = "io.github.syczk301.DockHush"
let accent = Color(red: 0.08, green: 0.48, blue: 0.39)
var eventTap: CFMachPort?
var tapSource: CFRunLoopSource?
var swallowed = false

struct AppRecord: Identifiable {
    let id: String
    let name: String
    let path: String
    let nativeAgent: Bool
    var displayName: String {id == helperID ? L("brand") : name}
    var icon: NSImage { NSWorkspace.shared.icon(forFile: path) }
    var isSystemApp: Bool { URL(fileURLWithPath: path).resolvingSymlinksInPath().path.hasPrefix("/System/") }
}

func running(_ id: String) -> NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
}
@discardableResult func hideApplication(_ id: String) -> Bool {
    guard let app = running(id) else { return false }
    if app.hide() { return true }
    return AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXHiddenAttribute as CFString, kCFBooleanTrue) == .success
}

final class Manager: ObservableObject {
    static let shared = Manager()
    @Published var apps: [AppRecord] = []
    @Published var managed: Set<String>
    @Published var dockManaged: Set<String>
    @Published var query = ""
    @Published var settingsPresented = false
    @Published var detailsPresented = false
    @Published var filter = "all"
    @Published var helperDockVisible = UserDefaults.standard.bool(forKey: "helperDockVisible")
    @Published var hideSystemApps = UserDefaults.standard.bool(forKey: "hideSystemApps") {
        didSet { UserDefaults.standard.set(hideSystemApps, forKey: "hideSystemApps") }
    }
    @Published var notice = L("intro")
    @Published var loading = false
    @Published var permission = false
    @Published var tick = 0
    @Published var busy: Set<String> = []
    let compatibility = DockCompatibility()
    let tempoRuntime = TempoRuntime()
    let kugouRuntime = KugouRuntime()
    @Published var compatibilityBusy = false
    var changed: (() -> Void)?
    init() {
        UserDefaults.standard.register(defaults: ["managedApps": [String](), "helperDockVisible": true, "hideSystemApps": true])
        managed = Set(UserDefaults.standard.stringArray(forKey: "managedApps") ?? [])
        dockManaged = Set(UserDefaults.standard.stringArray(forKey: "dockHiddenApps") ?? [])
        saveRuntimeRules()
    }
    var shown: [AppRecord] {
        apps.filter {
            (!hideSystemApps || !$0.isSystemApp) &&
            (query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)) &&
            (filter != "configured" || configured.contains($0.id)) &&
            (filter != "running" || running($0.id) != nil) &&
            (filter != "dock" || $0.id == helperID || $0.id == zspaceID || $0.id == tempoID || $0.id == KugouRuntime.id || compatibility.reason($0.path) == nil)
        }
    }
    func setHelperDockVisible(_ visible: Bool) {
        let window = NSApp.keyWindow
        guard NSApp.setActivationPolicy(visible ? .regular : .accessory) else {
            notice = L("self.dockFailed")
            return
        }
        helperDockVisible = visible
        UserDefaults.standard.set(visible, forKey: "helperDockVisible")
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        notice = visible ? L("self.dockShown") : L("self.dockHidden")
    }
    func scan() {
        guard !loading else { return }; loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let roots = ["/Applications", NSHomeDirectory()+"/Applications", "/System/Applications", "/System/Library/CoreServices/Applications"]
            var found: [String: AppRecord] = [:]
            func add(_ url: URL) {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
                let info = bundle.localizedInfoDictionary ?? bundle.infoDictionary ?? [:]
                let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
                let record = AppRecord(id:id, name:name, path:url.path, nativeAgent:(bundle.object(forInfoDictionaryKey:"LSUIElement") as? Bool == true || bundle.object(forInfoDictionaryKey:"LSBackgroundOnly") as? Bool == true))
                if found[id] == nil { found[id] = record }
            }
            for root in roots {
                guard let iter = fm.enumerator(at:URL(fileURLWithPath:root), includingPropertiesForKeys:[.isDirectoryKey], options:[.skipsHiddenFiles]) else {continue}
                for case let url as URL in iter {
                    if url.pathExtension.lowercased() == "app" { add(url); iter.skipDescendants() }
                    else if url.pathComponents.count > URL(fileURLWithPath:root).pathComponents.count + 3 { iter.skipDescendants() }
                }
            }
            for app in NSWorkspace.shared.runningApplications {
                if let url = app.bundleURL, app.activationPolicy == .regular { add(url) }
            }
            add(Bundle.main.bundleURL)
            let result = found.values.sorted {
                if $0.id == helperID { return $1.id != helperID }
                if $1.id == helperID { return false }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            DispatchQueue.main.async { self.apps = result; self.loading = false; self.changed?() }
        }
    }
    func saveRuntimeRules() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DockHush/rules.json")
        do {
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            let data = try JSONSerialization.data(withJSONObject:["close":Array(managed),"dock":Array(dockManaged)])
            try data.write(to:url,options:.atomic)
        } catch { notice = L("error.save", [String(describing: error.localizedDescription)]) }
    }
    var configured: Set<String> { managed.union(dockManaged).union([helperID]) }
    var zspaceHooked: Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DockHush/zspace-session.json")
        if let data = try? Data(contentsOf:url), let state = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
           state["rulesVersion"] as? Int == 2, let current = running(zspaceID), state["pid"] as? Int == Int(current.processIdentifier) {return true}
        return false
    }
    func applyZspaceRules() {
        if zspaceHooked { notice = L("zspace.updated") }
        else { launchZspace(hide:false) }
    }
    func setManaged(_ app: AppRecord, _ value: Bool) {
        if value { managed.insert(app.id) } else { managed.remove(app.id) }
        UserDefaults.standard.set(Array(managed).sorted(), forKey:"managedApps")
        saveRuntimeRules(); changed?()
        if app.id == zspaceID { applyZspaceRules() }
        else { notice = value ? L("close.enabled", [String(describing: app.displayName)]) : L("close.disabled", [String(describing: app.displayName)]) }
        if value && !permission && app.id != zspaceID { notice = L("close.permission") }
    }
    func dockEnabled(_ app: AppRecord) -> Bool {
        if app.id == helperID { return !helperDockVisible }
        if app.id == zspaceID { return dockManaged.contains(app.id) }
        if let current = running(app.id) {return current.activationPolicy != .regular}
        if app.id == tempoID || app.id == KugouRuntime.id { return dockManaged.contains(app.id) }
        if let setting = compatibility.active[app.id] {return setting.hidden}
        if app.nativeAgent { return true }
        return false
    }
    func setDock(_ app: AppRecord, _ value: Bool) {
        if app.id == helperID { setHelperDockVisible(!value); return }
        if app.id == tempoID { setTempoDock(app,value); return }
        if app.id == KugouRuntime.id { setKugouDock(app,value); return }
        if app.id != zspaceID {
            compatibilityBusy = true; busy.insert(app.id)
            compatibility.apply(id:app.id,path:app.path,hidden:value,progress:{self.notice=$0}) { success,message in
                self.compatibilityBusy=false; self.busy.remove(app.id); self.tick += 1
                if success {
                    if value {self.dockManaged.insert(app.id)} else {self.dockManaged.remove(app.id)}
                    UserDefaults.standard.set(Array(self.dockManaged).sorted(),forKey:"dockHiddenApps")
                    self.saveRuntimeRules(); self.changed?()
                }
                self.notice=message
            }
            return
        }
        if value {dockManaged.insert(app.id)} else {dockManaged.remove(app.id)}
        UserDefaults.standard.set(Array(dockManaged).sorted(),forKey:"dockHiddenApps")
        saveRuntimeRules(); changed?(); applyZspaceRules()
    }
    func saveTempoDock(_ hidden:Bool) {
        if hidden {dockManaged.insert(tempoID)} else {dockManaged.remove(tempoID)}
        UserDefaults.standard.set(Array(dockManaged).sorted(),forKey:"dockHiddenApps")
        saveRuntimeRules(); changed?()
    }
    func setTempoDock(_ app:AppRecord, _ hidden:Bool) {
        guard !busy.contains(tempoID) else {return}
        let previous=dockManaged.contains(tempoID)
        if tempoRuntime.isInstalled(running(tempoID)) {
            busy.insert(tempoID);saveTempoDock(hidden)
            tempoRuntime.waitForPolicy(hidden:hidden) {error in
                self.busy.remove(tempoID);self.tick += 1
                if let error=error {self.saveTempoDock(previous);self.notice=error}
                else {self.notice=L("tempo.ready")}
            }
            return
        }
        if !hidden {saveTempoDock(false);notice=L("tempo.shown");return}
        if let current=running(tempoID), current.bundleURL?.resolvingSymlinksInPath() != URL(fileURLWithPath:app.path).resolvingSymlinksInPath() {notice=L("error.otherCopy");return}
        let alert=NSAlert();alert.messageText=L("tempo.consentTitle");alert.informativeText=L("tempo.consentBody")
        alert.addButton(withTitle:L("tempo.consentAllow"));alert.addButton(withTitle:L("zspace.consentCancel"))
        guard alert.runModal() == .alertFirstButtonReturn else {return}
        busy.insert(tempoID);notice=L("tempo.preparing")
        DispatchQueue.global().async {
            let result=Result {try self.tempoRuntime.prepare(appPath:app.path)}
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):self.busy.remove(tempoID);self.notice=error.localizedDescription
                case .success(let plugins):
                    func start() {
                        self.saveTempoDock(true)
                        self.tempoRuntime.launch(appPath:app.path,plugins:plugins,hidden:true) {error in
                            if let error=error {
                                self.saveTempoDock(previous)
                                // A failed adapter never changes or re-signs the target app.
                                self.compatibility.quit(tempoID) {stopped in
                                    guard stopped else {self.busy.remove(tempoID);self.notice=L("tempo.fallbackQuitFailed",[error]);return}
                                    NSWorkspace.shared.openApplication(at:URL(fileURLWithPath:app.path),configuration:NSWorkspace.OpenConfiguration()) {_,fallbackError in
                                        DispatchQueue.main.async {
                                            self.busy.remove(tempoID);self.tick += 1
                                            self.notice=fallbackError == nil ? L("tempo.fallback",[error]) : L("error.open",[fallbackError!.localizedDescription])
                                        }
                                    }
                                }
                            } else {self.busy.remove(tempoID);self.tick += 1;self.notice=L("tempo.ready")}
                        }
                    }
                    if running(tempoID) != nil {
                        self.notice=L("tempo.restarting")
                        self.compatibility.quit(tempoID) {stopped in
                            if stopped {start()}
                            else {self.busy.remove(tempoID);self.notice=L("tempo.quitFailed")}
                        }
                    } else {start()}
                }
            }
        }
    }
    func setKugouDock(_ app:AppRecord, _ hidden:Bool) {
        let id=KugouRuntime.id
        guard !busy.contains(id) else {return}
        let target=URL(fileURLWithPath:app.path).resolvingSymlinksInPath()
        if NSRunningApplication.runningApplications(withBundleIdentifier:id).contains(where:{$0.bundleURL?.resolvingSymlinksInPath() != target}) {notice=L("error.otherCopy");return}
        func save() {
            if hidden {self.dockManaged.insert(id)} else {self.dockManaged.remove(id)}
            UserDefaults.standard.set(Array(self.dockManaged).sorted(),forKey:"dockHiddenApps")
            self.saveRuntimeRules();self.changed?()
        }
        if let current=running(id),current.activationPolicy == (hidden ? .accessory : .regular) {save();notice=L("kugou.ready");return}
        if !hidden && running(id)==nil {save();notice=L("kugou.ready");return}
        busy.insert(id);notice=L("kugou.preparing")
        kugouRuntime.preflight(path:app.path,hidden:hidden) {error in
            if let error=error {self.busy.remove(id);self.notice=error;return}
            func start() {
                self.kugouRuntime.apply(path:app.path,hidden:hidden) {error,attempted in
                    self.tick += 1
                    if let error=error {
                        guard attempted else {self.busy.remove(id);self.notice=error;return}
                        // Restore ordinary launch behavior after an unsuccessful agent launch.
                        let config=NSWorkspace.OpenConfiguration();config.activates=false;config.allowsRunningApplicationSubstitution=false
                        NSWorkspace.shared.openApplication(at:target,configuration:config) {_,fallbackError in
                            DispatchQueue.main.async {
                                self.busy.remove(id)
                                self.notice=fallbackError==nil ? L("kugou.fallback",[error]) : L("error.open",[fallbackError!.localizedDescription])
                            }
                        }
                    } else {save();self.busy.remove(id);self.notice=L("kugou.ready")}
                }
            }
            if hidden && running(id) != nil {
                let alert=NSAlert();alert.messageText=L("kugou.consentTitle");alert.informativeText=L("kugou.consentBody")
                alert.addButton(withTitle:L("tempo.consentAllow"));alert.addButton(withTitle:L("zspace.consentCancel"))
                guard alert.runModal() == .alertFirstButtonReturn else {self.busy.remove(id);return}
                self.notice=L("kugou.restarting")
                self.kugouRuntime.quit() {stopped in
                    if stopped {start()} else {self.busy.remove(id);self.notice=L("error.quitTimeout")}
                }
            } else {start()}
        }
    }
    func dockHelp(_ app: AppRecord) -> String {
        if app.id == helperID {return L("self.dockHelp")}
        if app.id == zspaceID {return L("dock.helpInstant")}
        if app.id == tempoID {return L("tempo.dockHelp")}
        if app.id == KugouRuntime.id {return L("kugou.dockHelp")}
        if let reason = compatibility.reason(app.path) {return reason}
        return L("dock.helpRestart")
    }
    func dockStatus(_ app: AppRecord) -> String {
        if app.id == helperID {return helperDockVisible ? L("dock.shown") : L("dock.hidden")}
        if let current = running(app.id) { return current.activationPolicy == .regular ? L("dock.shown") : L("dock.hidden") }
        if app.id == zspaceID { return L("dock.openToApply") }
        if app.id == tempoID { return L("tempo.openToApply") }
        if app.id == KugouRuntime.id { return dockManaged.contains(app.id) ? L("dock.savedHidden") : L("dock.savedShown") }
        if app.nativeAgent { return L("dock.native") }
        if let setting = compatibility.active[app.id] {return setting.hidden ? L("dock.savedHidden") : L("dock.savedShown")}
        return L("dock.restartNeeded")
    }
    func open(_ app: AppRecord) {
        if app.id == KugouRuntime.id && dockManaged.contains(app.id) && running(app.id)==nil {setKugouDock(app,true);return}
        if app.id == tempoID && dockManaged.contains(tempoID) && !tempoRuntime.isInstalled(running(tempoID)) {setTempoDock(app,true);return}
        if app.id == zspaceID { launchZspace(hide:false); return }
        if let current = running(app.id) {
            current.unhide()
            _ = AXUIElementSetAttributeValue(AXUIElementCreateApplication(current.processIdentifier), kAXHiddenAttribute as CFString, kCFBooleanFalse)
            current.activate(options:[.activateAllWindows])
            if app.id == tempoID || (app.id == KugouRuntime.id && current.activationPolicy == .accessory) {return}
        }
        NSWorkspace.shared.openApplication(at:URL(fileURLWithPath:app.path), configuration:NSWorkspace.OpenConfiguration()) { _, error in
            if let error = error { DispatchQueue.main.async { self.notice = L("error.open", [String(describing: error.localizedDescription)]) } }
        }
    }
    func hide(_ app: AppRecord) {
        if app.id == zspaceID && configured.contains(app.id) { launchZspace(hide:true); return }
        notice = hideApplication(app.id) ? L("app.hidden", [String(describing: app.displayName)]) : L("error.hideApp", [String(describing: app.displayName)])
        tick += 1
    }
    func launchZspace(hide: Bool, approved: Bool = false) {
        guard !busy.contains(zspaceID), let resource = Bundle.main.url(forResource:"zspace-switch-launch", withExtension:"mjs") else {return}
        let candidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node"] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator:":").map {String($0)+"/node"}
        guard let nodePath = candidates.first(where:{FileManager.default.isExecutableFile(atPath:$0)}) else {notice=L("zspace.nodeRequired");return}
        let nodeURL = URL(fileURLWithPath:nodePath)
        if !hide && !zspaceHooked {
            if !approved {
                let alert=NSAlert();alert.messageText=L("zspace.consentTitle");alert.informativeText=L("zspace.consentBody")
                alert.addButton(withTitle:L("zspace.consentAllow"));alert.addButton(withTitle:L("zspace.consentCancel"))
                guard alert.runModal() == .alertFirstButtonReturn else {notice=L("zspace.restart");return}
            }
            if running(zspaceID) != nil {
                busy.insert(zspaceID); notice=L("progress.quitting")
                compatibility.quit(zspaceID) { stopped in
                    self.busy.remove(zspaceID)
                    guard stopped else {self.notice=L("zspace.quitFailed");return}
                    self.launchZspace(hide:false, approved:true)
                }
                return
            }
        }
        busy.insert(zspaceID)
        notice = hide ? L("zspace.hiding") : L("zspace.opening")
        DispatchQueue.global().async {
            let process = Process(); process.executableURL = nodeURL
            process.arguments = [resource.path] + (hide ? ["--hide"] : [])
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
            do {
                try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                let logDir=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DockHush")
                try? FileManager.default.createDirectory(at:logDir,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                let logURL=logDir.appendingPathComponent("zspace.log")
                try? data.write(to:logURL,options:.atomic)
                try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:logURL.path)
                DispatchQueue.main.async {
                    self.busy.remove(zspaceID); self.tick += 1
                    self.notice = process.terminationStatus == 0 ? (hide ? L("zspace.hidden") : L("zspace.ready")) : L("zspace.failed")
                }
            } catch { DispatchQueue.main.async { self.busy.remove(zspaceID); self.notice = L("error.launch", [String(describing: error.localizedDescription)]) } }
        }
    }
    func openBackups() {
        let root=compatibility.root
        do {try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);NSWorkspace.shared.open(root)}
        catch {notice=L("error.open",[error.localizedDescription])}
    }
    func refreshPermission() {
        permission = AXIsProcessTrusted() && eventTap != nil
        if AXIsProcessTrusted() && eventTap == nil { installTap(); permission = eventTap != nil }
        tick += 1
    }
}

func interceptedApp(_ point: CGPoint) -> String? {
    let settings = Manager.shared.managed
    guard !settings.isEmpty else {return nil}
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.05)
    var hit: AXUIElement?
    if AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, let hit = hit {
        var pid: pid_t = 0; AXUIElementGetPid(hit, &pid)
        guard let id = NSRunningApplication(processIdentifier:pid)?.bundleIdentifier, settings.contains(id), id != zspaceID else {return nil}
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(hit,kAXSubroleAttribute as CFString,&subrole)
        if subrole as? String == kAXCloseButtonSubrole {return id}
        if id == KugouCloseButton.id {
            return KugouCloseButton.matches(hit:hit,point:point,pid:pid) ? id : nil
        }
        if id != tempoID {return nil}
    }
    // TempoHub draws its own red close button; use its existing verified adapter.
    guard settings.contains(tempoID), let app = running(tempoID) else {return nil}
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],0) as? [[String:Any]] ?? []
    for window in windows {
        guard window[kCGWindowLayer as String] as? Int == 0,
              let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation:bounds), rect.contains(point) else {continue}
        if window[kCGWindowOwnerPID as String] as? Int == Int(app.processIdentifier), rect.width >= 600, rect.height >= 400,
           CGRect(x:rect.minX+27,y:rect.minY+29,width:17,height:17).contains(point) {return tempoID}
        return nil
    }
    return nil
}
let tapCallback: CGEventTapCallBack = { _,type,event,_ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        swallowed = false
        if let tap = eventTap {CGEvent.tapEnable(tap:tap,enable:true)}
        return Unmanaged.passUnretained(event)
    }
    if type == .leftMouseUp && swallowed {swallowed = false; return nil}
    if type == .leftMouseDown, let id = interceptedApp(event.location) {
        swallowed = true
        DispatchQueue.main.async {
            if !hideApplication(id) {Manager.shared.notice = L("error.hideWindow")}
        }
        return nil
    }
    return Unmanaged.passUnretained(event)
}
func installTap() {
    guard eventTap == nil, AXIsProcessTrusted() else {return}
    let mask = (CGEventMask(1)<<CGEventType.leftMouseDown.rawValue) | (CGEventMask(1)<<CGEventType.leftMouseUp.rawValue)
    eventTap = CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:mask,callback:tapCallback,userInfo:nil)
    if let tap = eventTap {
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0)
        CFRunLoopAddSource(CFRunLoopGetMain(),tapSource,.commonModes)
        CGEvent.tapEnable(tap:tap,enable:true)
    }
}

struct Panel: View {
    @ObservedObject var model: Manager
    @ObservedObject var language = Language.shared
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:8) {
                    HStack(spacing:10) {
                        Image(systemName:"moon.zzz.fill").foregroundStyle(accent)
                        Text(L("brand")).font(.system(size:26,weight:.semibold))
                    }
                    Text(L("tagline")).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment:.trailing,spacing:5) {
                    Text("\(model.configured.count)").font(.system(size:28,weight:.medium,design:.rounded)).foregroundStyle(accent)
                    Text(L("configured.countLabel")).font(.caption).foregroundStyle(.secondary)
                }
                Button {model.settingsPresented.toggle()} label: {Image(systemName:"gearshape")}
                    .buttonStyle(.plain).font(.system(size:18)).padding(.leading,12)
                    .help(L("settings.title")).accessibilityLabel(L("settings.title"))
                    .popover(isPresented:$model.settingsPresented,arrowEdge:.trailing) {
                        VStack(alignment:.leading,spacing:16) {
                            Text(L("settings.title")).font(.headline)
                            Picker(L("settings.language"),selection:$language.selection) {
                                ForEach(AppLanguage.allCases,id:\.self) {Text($0.label).tag($0)}
                            }.pickerStyle(.menu).id(language.code)
                            Text(L("settings.languageHelp")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                            Divider()
                            Text(L("settings.permissions")).font(.headline)
                            HStack {
                                Button(L("settings.accessibility")) {NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)}
                                Button(L("settings.appManagement")) {NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!)}
                            }
                            Text(L("settings.managementHelp")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                            Button(L("settings.backups")) {model.openBackups()}
                        }.padding(22).frame(width:370)
                    }
            }.padding(26)
            HStack(spacing:12) {
                Image(systemName:model.permission ? "checkmark.shield.fill" : "hand.raised.fill").foregroundStyle(model.permission ? accent : .orange)
                VStack(alignment:.leading,spacing:3) {
                    Text(model.permission ? L("permission.ready") : L("permission.needed")).font(.system(size:13,weight:.semibold))
                    Text(model.permission ? L("permission.readyHelp") : L("permission.help")).font(.system(size:12)).foregroundStyle(.secondary)
                }
                Spacer()
                if !model.permission {
                    Button(L("permission.open")) { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
                }
            }.padding(14).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:12)).padding(.horizontal,26)
            HStack {
                HStack { Image(systemName:"magnifyingglass").foregroundStyle(.secondary); TextField(L("search"),text:$model.query).textFieldStyle(.plain) }
                    .padding(9).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:8)).frame(width:260)
                Spacer()
                Toggle(L("filter.hideSystem"), isOn: $model.hideSystemApps)
                    .toggleStyle(.switch).tint(.blue).controlSize(.small)
                    .help(L("filter.hideSystemHelp"))
                Picker(L("filter.label"),selection:$model.filter) {
                    ForEach(["all","configured","running","dock"],id:\.self) {Text(L("filter."+$0)).tag($0)}
                }.labelsHidden().id(language.code).frame(width:185)
                Button {model.scan()} label: {Image(systemName:"arrow.clockwise")}.help(L("refresh")).accessibilityLabel(L("refresh"))
            }.padding(.horizontal,26).padding(.vertical,18)
            HStack {
                Text(L("column.app")).frame(maxWidth:.infinity,alignment:.leading)
                Text(L("column.close")).frame(width:120)
                Text(L("column.dock")).frame(width:120)
            }.font(.system(size:11,weight:.semibold)).foregroundStyle(.secondary).padding(.horizontal,26).padding(.bottom,10)
            Divider()
            ScrollView {
                LazyVStack(spacing:0) {
                    ForEach(model.shown) {app in
                        HStack(spacing:0) {
                            HStack(spacing:11) {
                                Image(nsImage:app.icon).resizable().frame(width:32,height:32)
                                VStack(alignment:.leading,spacing:4) {
                                    Text(app.displayName).font(.system(size:13,weight:.medium)).lineLimit(1)
                                    if app.id == KugouCloseButton.id {
                                        Text(L("kugou.label")).font(.system(size:10)).foregroundStyle(.secondary)
                                    }
                                    if app.id == tempoID {
                                        Text(L("tempo.dockLabel")).font(.system(size:10)).foregroundStyle(.secondary)
                                    }
                                    HStack(spacing:5) {
                                        Circle().fill(running(app.id) == nil ? Color.gray.opacity(0.35) : accent).frame(width:5,height:5)
                                        Text(running(app.id) == nil ? L("status.stopped") : L("status.running")).font(.system(size:10)).foregroundStyle(.secondary)
                                    }
                                }
                            }.frame(maxWidth:.infinity,alignment:.leading).help(L("app.help", [String(describing: app.path), String(describing: model.dockStatus(app))]))
                            .contextMenu {
                                Button(L("action.open")) {model.open(app)}
                                Button(L("action.hide")) {model.hide(app)}.disabled(running(app.id) == nil)
                            }
                            Toggle(L("accessibility.close", [String(describing: app.displayName)]),isOn:Binding(get:{app.id == helperID || model.managed.contains(app.id)},set:{model.setManaged(app,$0)}))
                                .labelsHidden().toggleStyle(.switch).tint(.blue).controlSize(.regular).frame(width:120)
                                .disabled(app.id == helperID || model.busy.contains(app.id))
                                .help(app.id == helperID ? L("self.closeHelp") : L("close.help"))
                            Toggle(L("accessibility.dock", [String(describing: app.displayName)]),isOn:Binding(get:{!model.dockEnabled(app)},set:{model.setDock(app,!$0)}))
                                .labelsHidden().toggleStyle(.switch).tint(.blue).controlSize(.regular).frame(width:120)
                                .disabled(model.compatibilityBusy || model.compatibility.busy || model.busy.contains(app.id) || (app.id != zspaceID && app.id != helperID && app.id != tempoID && app.id != KugouRuntime.id && model.compatibility.reason(app.path) != nil)).help(model.dockHelp(app))
                        }.padding(.horizontal,26).padding(.vertical,12)
                        Divider().padding(.horizontal,26)
                    }
                    if model.shown.isEmpty {Text(model.loading ? L("status.scanning") : L("status.empty")).foregroundStyle(.secondary).padding(40)}
                }
            }
            Divider()
            VStack(alignment:.leading,spacing:7) {
                HStack(alignment:.top) {
                    Text(language.render(model.notice)).font(.system(size:12)).foregroundStyle(accent).lineLimit(2)
                    Spacer(minLength:8)
                    Button(L("settings.details")) {model.detailsPresented=true}.font(.system(size:11))
                }
                Text(L("footer", [String(describing: model.apps.count)])).font(.system(size:11)).foregroundStyle(.secondary)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,26).padding(.vertical,14)
        }.frame(minWidth:860,minHeight:590).background(Color(nsColor:.windowBackgroundColor))
        .sheet(isPresented:$model.detailsPresented) {
            VStack(alignment:.leading,spacing:18) {
                Text(L("settings.details")).font(.headline)
                ScrollView {Text(language.render(model.notice)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}.frame(maxHeight:240)
                HStack {
                    Button(L("settings.backups")) {model.openBackups()}
                    Spacer()
                    Button(L("settings.done")) {model.detailsPresented=false}.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width:540)
        }
    }
}

final class Delegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var panel: NSWindow?
    let manager = Manager.shared
    func applicationDidFinishLaunching(_ notification: Notification) {
        rebuildMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        if let url = Bundle.main.url(forResource:"StatusMoon",withExtension:"png"), let image = NSImage(contentsOf:url) {image.size=NSSize(width:20,height:20);image.isTemplate=true;statusItem.button?.image=image}
        else {statusItem.button?.image=NSImage(systemSymbolName:"moon.zzz",accessibilityDescription:L("brand"))}
        statusItem.button?.toolTip=L("menu.tooltip")
        manager.changed = { [weak self] in self?.updateMenu() }
        Language.shared.onChange = { [weak self] in
            self?.rebuildMainMenu();self?.updateMenu();self?.panel?.title=L("brand")
            self?.statusItem.button?.toolTip=L("menu.tooltip")
        }
        installTap(); manager.refreshPermission(); updateMenu(); manager.scan()
        manager.compatibility.recover {self.manager.notice=$0}
        Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in self?.manager.refreshPermission() }
        if !CommandLine.arguments.contains("--background") {showPanel()}
    }
    func rebuildMainMenu() {
        let menu = NSMenu()
        let applicationMenu = NSMenuItem(); menu.addItem(applicationMenu)
        let submenu = NSMenu(); submenu.addItem(withTitle:L("menu.quit"),action:#selector(stop),keyEquivalent:"q"); applicationMenu.submenu = submenu
        let editItem = NSMenuItem(); menu.addItem(editItem); let edit = NSMenu(title:L("menu.edit")); editItem.submenu = edit
        edit.addItem(withTitle:L("menu.copy"),action:#selector(NSText.copy(_:)),keyEquivalent:"c")
        edit.addItem(withTitle:L("menu.paste"),action:#selector(NSText.paste(_:)),keyEquivalent:"v")
        edit.addItem(withTitle:L("menu.selectAll"),action:#selector(NSText.selectAll(_:)),keyEquivalent:"a")
        submenu.insertItem(withTitle:L("menu.settings"),action:#selector(showSettings),keyEquivalent:",",at:0)
        for item in submenu.items {item.target=self}
        applicationMenu.title=L("brand")
        editItem.title=L("menu.edit")
        NSApp.mainMenu = menu
    }
    @objc func showSettings() {showPanel();manager.settingsPresented=true}
    func updateMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle:L("menu.open"),action:#selector(showPanel),keyEquivalent:"")
        menu.addItem(withTitle:L("menu.settings"),action:#selector(showSettings),keyEquivalent:",")
        menu.addItem(.separator())
        for app in manager.apps.filter({manager.configured.contains($0.id)}) {
            let item=NSMenuItem(title:L("menu.openApp", [String(describing: app.displayName)]),action:#selector(openManaged(_:)),keyEquivalent:"");item.representedObject=app.id;menu.addItem(item)
        }
        menu.addItem(.separator()); menu.addItem(withTitle:L("menu.quit"),action:#selector(stop),keyEquivalent:"")
        for item in menu.items {item.target=self};statusItem.menu=menu
    }
    @objc func openManaged(_ sender: NSMenuItem) {if let id=sender.representedObject as? String,let app=manager.apps.first(where:{$0.id==id}) {manager.open(app)}}
    @objc func showPanel() {
        if panel == nil {
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:860,height:690),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title=L("brand");window.titlebarAppearsTransparent=true;window.isReleasedWhenClosed=false;window.delegate=self
            window.contentView=NSHostingView(rootView:Panel(model:manager));window.center();panel=window
        }
        panel?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {showPanel();return true}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
    @objc func stop() {NSApp.terminate(nil)}
}
UserDefaults.standard.register(defaults:["helperDockVisible":true,"hideSystemApps":true])
let application=NSApplication.shared
if NSWorkspace.shared.runningApplications.contains(where:{$0.bundleIdentifier==helperID && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier}) {exit(0)}
application.setActivationPolicy(UserDefaults.standard.bool(forKey: "helperDockVisible") ? .regular : .accessory)
let delegate=Delegate();application.delegate=delegate;application.run()
