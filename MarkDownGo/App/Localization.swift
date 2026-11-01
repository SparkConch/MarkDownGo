import Foundation
import MarkDownGoCore

/// Live language switching: look the string up in the bundle for the chosen language instead of
/// letting the system pick once at launch. `AppleLanguages` is still written so native panels
/// (open/save dialogs) match on next launch, but our own UI switches immediately.
enum Localization {
    private static var cache: [String: Bundle] = [:]

    static var currentBundle: Bundle {
        let language = Preferences.language
        guard language != .system else { return .main }
        if let cached = cache[language.rawValue] { return cached }
        if let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            cache[language.rawValue] = bundle
            return bundle
        }
        return .main
    }

    static func string(_ key: String) -> String {
        let chosen = currentBundle.localizedString(forKey: key, value: "\u{0}", table: nil)
        if chosen != "\u{0}" { return chosen }
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}
