import AppKit
let root=URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("fixture")
try FileManager.default.createDirectory(at:root.appendingPathComponent("Contents"),withIntermediateDirectories:true)
let service=DockCompatibility(root:root.appendingPathComponent("records"))
let original=try PropertyListSerialization.data(fromPropertyList:["CFBundleIdentifier":"com.edifier.connectHD","CFBundleExecutable":"Probe","SignedMarker":"vendor-original"],format:.xml,options:0)
let plist=service.plist(root.path)
try original.write(to:plist)
func check(_ condition:Bool,_ label:String) {print((condition ? "PASS: ":"FAIL: ")+label);if !condition {exit(1)}}
check(service.reason(root.path) == L("tempo.dockUnsupported"),"TempoHub Dock control explains signature protection")
for hidden in [true,false] {
 var completed=false
 service.apply(id:"com.edifier.connectHD",path:root.path,hidden:hidden,progress:{_ in fatalError("Must not quit or launch TempoHub")}) {ok,message in
  completed=true;check(!ok && message == L("tempo.dockUnsupported"),"unsafe Dock change rejected")
 }
 check(completed && !service.busy,"rejected operation completes immediately")
 check(try Data(contentsOf:plist)==original,"vendor configuration remains byte-for-byte unchanged")
 check(!FileManager.default.fileExists(atPath:service.root.path),"no compatibility transaction is created")
}
let dir=service.root.appendingPathComponent("legacy")
try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
let record=DockCompatibility.Record(id:"com.edifier.connectHD",path:root.path,executable:"/unused",executableHash:"old-hash",baseline:original,before:Data("unsafe old backup".utf8),target:original,hidden:true,wasRunning:true,phase:"verifying",date:Date())
try service.save(record,dir)
var completed=false
service.restore(record,dir:dir) {ok,_ in completed=true;check(!ok,"legacy recovery refuses to replay old configuration")}
check(completed,"legacy recovery completes without launching or quitting an app")
check(try Data(contentsOf:plist)==original,"legacy recovery preserves current signed configuration")
check(service.pending.first?.1.phase == "conflict","legacy recovery remains visible for manual review")
check(service.pending.first?.1.before==record.before,"legacy backup evidence is retained")
print("ALL PASS")
