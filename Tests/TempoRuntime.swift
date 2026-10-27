import AppKit
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let adapter=root.appendingPathComponent("adapter.dylib")
let bytes=Data("test adapter bytes - never loaded".utf8);try bytes.write(to:adapter)
let runtime=TempoRuntime(root:root.appendingPathComponent("support"),adapter:adapter)
let installed=try runtime.installedPath();try FileManager.default.createDirectory(at:installed.deletingLastPathComponent(),withIntermediateDirectories:true)
try bytes.write(to:installed)
let now=Date()
var state:[String:Any]=["pid":42,"adapterVersion":1,"adapterPath":installed.resolvingSymlinksInPath().path,"launchTime":123.0,"updatedAt":now.timeIntervalSince1970]
func check(_ ok:Bool,_ label:String){print((ok ? "PASS: ":"FAIL: ")+label);if !ok {exit(1)}}
func valid()->Bool {runtime.matchesSession(state,pid:42,launchTime:123,now:now)}
check(valid(),"matching runtime session accepted")
state["pid"]=43;check(!valid(),"different process rejected");state["pid"]=42
state["launchTime"]=120.0;check(!valid(),"reused PID rejected");state["launchTime"]=123.0
state["updatedAt"]=now.timeIntervalSince1970-10;check(!valid(),"stale adapter heartbeat rejected");state["updatedAt"]=now.timeIntervalSince1970
state["adapterPath"]="/other/plugin.dylib";check(!valid(),"unexpected adapter path rejected");state["adapterPath"]=installed.resolvingSymlinksInPath().path
try Data("tampered".utf8).write(to:installed);check(!valid(),"modified adapter rejected");try bytes.write(to:installed)
state["adapterVersion"]=2;check(!valid(),"unsupported session version rejected")
check(!runtime.isInstalled(nil),"stopped app never reports installed")
let app=root.appendingPathComponent("unsupported-fixture")
let cocoa=app.appendingPathComponent("Contents/Frameworks/PyQt6/Qt6/plugins/platforms/libqcocoa.dylib")
try FileManager.default.createDirectory(at:cocoa.deletingLastPathComponent(),withIntermediateDirectories:true)
let plist=app.appendingPathComponent("Contents/Info.plist")
let original=try PropertyListSerialization.data(fromPropertyList:["CFBundleIdentifier":TempoRuntime.id],format:.xml,options:0);try original.write(to:plist)
try Data(Array("QTMETADATA !".utf8)+[1,6,8,0]).write(to:cocoa)
do {_ = try runtime.prepare(appPath:app.path);check(false,"unsupported Qt must fail before launching")}catch {check(error.localizedDescription==L("tempo.qtUnsupported"),"unsupported Qt rejected without running signature or launch tools")}
check(try Data(contentsOf:plist)==original,"version validation does not edit app files")
if CommandLine.arguments.count>2 {
 let path=CommandLine.arguments[2]
 let info=URL(fileURLWithPath:path).appendingPathComponent("Contents/Info.plist")
 let before=try Data(contentsOf:info)
 _ = try runtime.prepare(appPath:path)
 check(try Data(contentsOf:info)==before,"installed vendor app signature validation succeeds without modifying Info.plist")
}
print("ALL PASS")
