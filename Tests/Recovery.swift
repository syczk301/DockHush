import AppKit
let app=NSApplication.shared;app.setActivationPolicy(.accessory)
let base=URL(fileURLWithPath:CommandLine.arguments[1])
let service=DockCompatibility(root:base.appendingPathComponent("recovery-records"))
func check(_ ok:Bool,_ label:String){print(label+": "+(ok ? "PASS":"FAIL"));if !ok{exit(1)}}
func record(_ kind:String)->DockCompatibility.Record {
 let path=base.appendingPathComponent(kind+"DockProbe.app").path
 let bytes=try! Data(contentsOf:service.plist(path))
 return .init(id:"io.github.syczk301.DockHush.test."+kind.lowercased(),path:path,executable:path+"/Contents/MacOS/Probe",executableHash:try! service.hash(path+"/Contents/MacOS/Probe"),baseline:bytes,before:bytes,target:bytes,hidden:false,wasRunning:false,phase:"prepared",date:Date())
}
func crashRecovery(){
 var r=record("Native")
 var info=try! PropertyListSerialization.propertyList(from:r.before,format:nil) as! [String:Any]
 info["LSUIElement"]=true;r.target=try! PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0);r.phase="applied";r.hidden=true
 let dir=service.root.appendingPathComponent(UUID().uuidString)
 try! FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
 try! service.save(r,dir);try! service.write(r.target,to:service.plist(r.path),expecting:r.before)
 let recovered=DockCompatibility(root:service.root)
 recovered.recover{print($0)}
 func poll(){
  if recovered.busy {DispatchQueue.main.asyncAfter(deadline:.now()+0.2,execute:poll);return}
  check(recovered.pending.isEmpty,"interrupted transaction recovered")
  check((try? Data(contentsOf:service.plist(r.path)))==r.before,"crash recovery exact bytes")
  // An unrelated edit must not be overwritten by recovery.
  r.date=Date();r.phase="applied";let conflictDir=service.root.appendingPathComponent(UUID().uuidString)
  try! FileManager.default.createDirectory(at:conflictDir,withIntermediateDirectories:true);try! service.save(r,conflictDir)
  info["ProbeUnrelatedEdit"]=true;let changed=try! PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0)
  try! service.write(changed,to:service.plist(r.path),expecting:r.before)
  let conflict=DockCompatibility(root:service.root);conflict.recover{print($0)}
  check((try? Data(contentsOf:service.plist(r.path)))==changed,"unrelated edit preserved")
  check(conflict.pending.first?.1.phase == "conflict","conflict reported")
  try! service.write(r.before,to:service.plist(r.path),expecting:changed)
  print("ALL PASS");exit(0)
 }
 poll()
}
DispatchQueue.main.async {
 let r=record("Override")
 service.launch(r,verify:false){error in
  check(error == nil,"start existing app")
  service.apply(id:r.id,path:r.path,hidden:true,progress:{print($0)}){success,message in
   print(message);check(!success,"failed hide rollback for running app")
   check(service.instances(r.id).first?.activationPolicy == .regular,"original app reopened and shown")
   check((try? Data(contentsOf:service.plist(r.path)))==r.before,"running app exact restoration")
   service.quit(r.id){_ in
    let e=record("Exit")
    service.apply(id:e.id,path:e.path,hidden:true,progress:{print($0)}){success,message in
     print(message);check(!success,"launch failure detected")
     check((try? Data(contentsOf:service.plist(e.path)))==e.before,"launch failure original restored")
     crashRecovery()
    }
   }
  }
 }
}
app.run()
