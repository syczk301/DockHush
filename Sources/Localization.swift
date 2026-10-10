import AppKit
import Combine

enum AppLanguage: String, CaseIterable {
    case system, simplifiedChinese = "zh-Hans", english = "en"
    var label: String {
        switch self {
        case .system: return L("settings.system")
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }
}

final class Language: ObservableObject {
    static let shared = Language()
    @Published var selection: AppLanguage {
        didSet {
            UserDefaults.standard.set(selection.rawValue, forKey:"appLanguage")
            onChange?()
        }
    }
    var onChange: (() -> Void)?
    let catalog: [String:[String:String]]
    private struct Message { let key:String; let args:[String] }
    private var messages: [String:Message] = [:]
    private let lock = NSLock()
    init() {
        selection = AppLanguage(rawValue:UserDefaults.standard.string(forKey:"appLanguage") ?? "system") ?? .system
        let resource = Bundle.main.url(forResource:"DockHushStrings",withExtension:"json") ?? Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("DockHushStrings.json")
        if let resource=resource, let data=try? Data(contentsOf:resource), let parsed=try? JSONDecoder().decode([String:[String:String]].self,from:data) {catalog=parsed}
        else {catalog=[:]}
        NotificationCenter.default.addObserver(forName:NSLocale.currentLocaleDidChangeNotification,object:nil,queue:.main) { [weak self] _ in
            guard let self=self,self.selection == .system else{return}
            self.objectWillChange.send();self.onChange?()
        }
    }
    var code: String {
        switch selection {
        case .simplifiedChinese:return "zh-Hans"
        case .english:return "en"
        case .system:
            let preferred=Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en"
            return preferred.lowercased().hasPrefix("zh") ? "zh-Hans" : "en"
        }
    }
    func text(_ key:String,_ args:[String]=[]) -> String {
        let template=catalog[key]?[code] ?? catalog[key]?["en"] ?? key
        let regex=try! NSRegularExpression(pattern:"\\{(\\d+)\\}")
        var result=template
        for match in regex.matches(in:template,range:NSRange(template.startIndex...,in:template)).reversed() {
            let n=Int((template as NSString).substring(with:match.range(at:1)))!
            if n<args.count,let range=Range(match.range,in:result) {result.replaceSubrange(range,with:render(args[n]))}
        }
        lock.lock();messages[result]=Message(key:key,args:args);lock.unlock()
        return result
    }
    // Keep already displayed operation results in the selected language too.
    func render(_ value:String) -> String {
        lock.lock();let message=messages[value];lock.unlock()
        guard let message=message else{return value}
        return text(message.key,message.args)
    }
}
func L(_ key:String,_ args:[String]=[]) -> String {Language.shared.text(key,args)}
