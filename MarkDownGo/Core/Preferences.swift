import Foundation

/// User-facing preferences, stored in `UserDefaults` so SwiftUI's `@AppStorage` can bind to the same
/// keys without a second source of truth.
public enum PreferenceKey {
    public static let fontSize = "mdg.fontSize"
    public static let softWrap = "mdg.softWrap"
    public static let lineNumbers = "mdg.lineNumbers"
    public static let imageMode = "mdg.imageMode"
    public static let language = "mdg.language"
    public static let appearance = "mdg.appearance"
}

/// Light / dark / follow the system. Mapped to `NSAppearance` in the app layer (Core stays AppKit-free).
public enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system: return NSLocalizedString("settings.appearance.system", comment: "")
        case .light: return NSLocalizedString("settings.appearance.light", comment: "")
        case .dark: return NSLocalizedString("settings.appearance.dark", comment: "")
        }
    }
}

public enum InterfaceLanguage: String, CaseIterable {
    case system
    case english = "en"
    case chinese = "zh-Hans"

    public var displayName: String {
        switch self {
        case .system: return NSLocalizedString("settings.language.system", comment: "")
        case .english: return "English"
        case .chinese: return "中文"
        }
    }
}

public enum Preferences {
    public static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PreferenceKey.fontSize: 15.0,
            PreferenceKey.softWrap: true,
            PreferenceKey.lineNumbers: true,
            PreferenceKey.imageMode: ImageStore.Mode.directory.rawValue,
            PreferenceKey.language: InterfaceLanguage.system.rawValue,
            PreferenceKey.appearance: AppearanceMode.system.rawValue,
        ])
    }

    public static var fontSize: Double { (UserDefaults.standard.object(forKey: PreferenceKey.fontSize) as? Double) ?? 15 }
    public static var softWrap: Bool { UserDefaults.standard.bool(forKey: PreferenceKey.softWrap) }
    public static var lineNumbers: Bool { UserDefaults.standard.bool(forKey: PreferenceKey.lineNumbers) }

    public static var imageMode: ImageStore.Mode {
        ImageStore.Mode(rawValue: UserDefaults.standard.string(forKey: PreferenceKey.imageMode) ?? "") ?? .directory
    }

    public static var appearance: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: PreferenceKey.appearance) ?? "") ?? .system
    }

    public static var language: InterfaceLanguage {
        InterfaceLanguage(rawValue: UserDefaults.standard.string(forKey: PreferenceKey.language) ?? "") ?? .system
    }

    /// Applies the language override through `AppleLanguages` (read at launch, so a relaunch is
    /// required). Returns whether a restart is needed to take effect.
    @discardableResult
    public static func applyLanguage(_ language: InterfaceLanguage) -> Bool {
        let current = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first
        switch language {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            return current != nil
        case .english:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
            return current != "en"
        case .chinese:
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
            return current != "zh-Hans"
        }
    }

    public static let didChange = Notification.Name("mdg.preferencesDidChange")
}

extension Preferences {
    /// Post after any preference change so live windows can re-apply without polling.
    public static func notifyChanged() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
