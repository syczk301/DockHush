import Foundation
let language = Language.shared
let before=UserDefaults.standard.object(forKey:"appLanguage")
defer {if let before=before {UserDefaults.standard.set(before,forKey:"appLanguage")} else {UserDefaults.standard.removeObject(forKey:"appLanguage")}}
precondition(!language.catalog.isEmpty)
language.selection = .simplifiedChinese
precondition(L("brand")=="隐坞 DockHush")
let notice=L("footer",["128"])
let path="/tmp/example/{0}/文件.app"
let detail=L("result.backup",[L("error.unsupported"),path])
language.selection = .english
precondition(L("brand")=="DockHush")
precondition(language.render(notice)==L("footer",["128"]))
precondition(language.render(detail).contains(path))
precondition(language.render(detail).contains("Backup location:"))
precondition(L("filter.running")=="Running")
print("Language switch, prior-result translation and literal argument preservation: PASS")
