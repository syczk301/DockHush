import AppKit
class D: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ n:Notification) {
        window=NSWindow(contentRect:NSRect(x:300,y:250,width:520,height:320),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title="DockHush Test Fixture"; window.isReleasedWhenClosed=false
        let label=NSTextField(labelWithString:"只用于验证：点叉后窗口隐藏，进程应保持运行。")
        label.frame=NSRect(x:25,y:135,width:480,height:40); window.contentView?.addSubview(label)
        window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
}
let app=NSApplication.shared; let d=D();app.delegate=d;app.run()
