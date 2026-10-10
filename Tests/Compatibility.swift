import AppKit
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
let base=URL(fileURLWithPath:CommandLine.arguments[1])
let service=DockCompatibility(root:base.appendingPathComponent("records"))
let native=base.appendingPathComponent("NativeDockProbe.app").path
let override=base.appendingPathComponent("OverrideDockProbe.app").path
let original=try! Data(contentsOf:service.plist(native))
let overrideOriginal=try! Data(contentsOf:service.plist(override))
func require(_ condition:Bool,_ message:String) {print(message+": "+(condition ? "PASS":"FAIL"));if !condition {exit(1)}}
DispatchQueue.main.async {
 service.apply(id:"io.github.syczk301.DockHush.test.native",path:native,hidden:true,progress:{print($0)}) {success,message in
  print(message);require(success,"native hide")
  require(service.instances("io.github.syczk301.DockHush.test.native").first?.activationPolicy == .accessory,"native hidden and alive")
  service.apply(id:"io.github.syczk301.DockHush.test.native",path:native,hidden:false,progress:{print($0)}) {success,message in
   print(message);require(success,"native show")
   require((try? Data(contentsOf:service.plist(native)))==original,"exact original bytes restored")
   require(service.instances("io.github.syczk301.DockHush.test.native").first?.activationPolicy == .regular,"native shown and alive")
   service.apply(id:"io.github.syczk301.DockHush.test.override",path:override,hidden:true,progress:{print($0)}) {success,message in
    print(message);require(!success,"override rejected")
    require((try? Data(contentsOf:service.plist(override)))==overrideOriginal,"failed hide automatically restored bytes")
    require(service.instances("io.github.syczk301.DockHush.test.override").isEmpty,"failed previously stopped app remains stopped")
    service.quit("io.github.syczk301.DockHush.test.native") {_ in print("ALL PASS");exit(0)}
   }
  }
 }
}
app.run()
