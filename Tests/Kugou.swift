import AppKit

func check(_ condition:Bool,_ label:String) {
    print((condition ? "PASS: " : "FAIL: ")+label)
    if !condition {exit(1)}
}
let window=CGRect(x:524,y:125,width:1152,height:800)
let close=CGRect(x:532,y:133,width:16,height:16)
let point=CGPoint(x:540,y:141)
check(KugouCloseButton.exactHit(point:point,hit:close,close:close,window:window),"Catalyst close-button geometry matches")
for other in [close.offsetBy(dx:20,dy:0),close.offsetBy(dx:40,dy:0),window,CGRect.zero] {
    check(!KugouCloseButton.exactHit(point:point,hit:other,close:close,window:window),"neighboring or container controls are not intercepted")
}
check(!KugouCloseButton.exactHit(point:CGPoint(x:550,y:141),hit:close,close:close,window:window),"outside click is not intercepted")
check(!KugouCloseButton.exactHit(point:point,hit:close,close:close,window:window.offsetBy(dx:500,dy:0)),"stale window geometry is rejected")
check(!KugouCloseButton.exactHit(point:point,hit:window,close:window,window:window),"oversized close-button geometry is rejected")
let shifted=close.offsetBy(dx:-1600,dy:-900)
check(KugouCloseButton.exactHit(point:CGPoint(x:point.x-1600,y:point.y-900),hit:shifted,close:shifted,window:window.offsetBy(dx:-1600,dy:-900)),"secondary-display coordinates work")

let root=URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("fixture")
try FileManager.default.createDirectory(at:root.appendingPathComponent("Contents"),withIntermediateDirectories:true)
let service=DockCompatibility(root:root.appendingPathComponent("records"))
let original=try PropertyListSerialization.data(fromPropertyList:["CFBundleIdentifier":KugouCloseButton.id,"CFBundleExecutable":"Probe"],format:.xml,options:0)
let plist=service.plist(root.path)
try original.write(to:plist)
check(service.reason(root.path)==L("kugou.dockUnsupported"),"writable Kugou copies also preserve the vendor bundle")
for hidden in [true,false] {
    var completed=false
    service.apply(id:KugouCloseButton.id,path:root.path,hidden:hidden,progress:{_ in fatalError("Must not quit or launch Kugou")}) {ok,message in
        completed=true;check(!ok && message==L("kugou.dockUnsupported"),"unsupported Dock change is rejected")
    }
    check(completed && !service.busy,"rejection completes without starting a transaction")
    check(try Data(contentsOf:plist)==original,"vendor configuration is unchanged")
    check(!FileManager.default.fileExists(atPath:service.root.path),"no compatibility transaction created")
}
let dir=service.root.appendingPathComponent("legacy")
try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
let record=DockCompatibility.Record(id:KugouCloseButton.id,path:root.path,executable:"/unused",executableHash:"old",baseline:original,before:Data("old backup".utf8),target:original,hidden:true,wasRunning:true,phase:"verifying",date:Date())
try service.save(record,dir)
var completed=false
service.restore(record,dir:dir) {ok,_ in completed=true;check(!ok,"legacy restore cannot overwrite the signed app")}
let afterRestore=try Data(contentsOf:plist)
check(completed && afterRestore==original,"restore leaves current configuration unchanged")
check(service.pending.first?.1.phase=="conflict" && service.pending.first?.1.before==record.before,"conflicting backup remains available for review")

let supported:[String:Any]=["CFBundleIdentifier":KugouRuntime.id,"CFBundleShortVersionString":"20.3.8","CFBundleVersion":"3898"]
check(KugouRuntime.supportedInfo(supported),"tested Kugou version accepted")
for (key,value) in [("CFBundleIdentifier","other.app"),("CFBundleShortVersionString","21.0"),("CFBundleVersion","9999")] {
    var info=supported;info[key]=value
    check(!KugouRuntime.supportedInfo(info),"unsupported identity or version rejected")
}
let runtime=KugouRuntime()
for hidden in [true,false] {
    let config=try runtime.configuration(hidden:hidden)
    let options=config.value(forKey:"_additionalLSOpenOptions") as? [String:Bool]
    let key=hidden ? "_kLSOpenOptionUIElementLaunchKey" : "_kLSOpenOptionForegroundLaunchKey"
    check(options==[key:true],"correct Launch Services type requested")
    check(!config.allowsRunningApplicationSubstitution && !config.activates,"launch cannot substitute another installed copy")
}
