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
    public static let theme = "mdg.theme"
    public static let quickLookMode = "mdg.quickLookMode"
    /// Read by the QuickLook extension through this suite name (the extension can't see
    /// UserDefaults.standard of the host app; see SPEC §4 on why no App Group is needed).
    public static let sharedSuite = "com.sparkconch.MarkDownGo"
    /// The QuickLook extension's own preference domain. A sandboxed extension reads
    /// `UserDefaults.standard` → its own domain, and an App Group is unavailable to ad-hoc signed
    /// builds (it demands a provisioning profile), so the host writes into *this* domain instead.
    /// The extension then needs no cross-process trickery at all.
    public static let extensionDomain = "com.sparkconch.MarkDownGo.quicklook"
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
            PreferenceKey.theme: Theme.fallback.id,
            PreferenceKey.quickLookMode: QuickLookMode.rendered.rawValue,
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

    public static var theme: Theme {
        Theme.named(UserDefaults.standard.string(forKey: PreferenceKey.theme) ?? Theme.fallback.id)
    }

    public static var quickLookMode: QuickLookMode {
        QuickLookMode(rawValue: UserDefaults.standard.string(forKey: PreferenceKey.quickLookMode) ?? "") ?? .rendered
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


extension Preferences {
    /// Daemon-side read used by the QuickLook extension. The extension runs in its own process with
    /// its own UserDefaults domain, so it opens the host app's domain by suite name.
    /// A sandboxed extension sees only its own container, and an App Group needs a provisioning
    /// profile (unavailable to ad-hoc builds). So the host writes a small JSON file *inside the
    /// extension's container* and the extension reads that: same user, no special entitlement,
    /// and no cfprefsd cache to fight.
    public static var extensionConfigURL: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Inside the sandbox the home directory *is* the container's Data folder; outside it we
        // have to reach into the container by name. Both spellings must resolve to one file.
        let containerData = home.path.contains("/Library/Containers/")
            ? home
            : home.appendingPathComponent("Library/Containers/\(PreferenceKey.extensionDomain)/Data", isDirectory: true)
        return containerData
            .appendingPathComponent("Library/Application Support/MarkDownGo", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    /// Written by the host whenever the theme or preview mode changes.
    @discardableResult
    public static func writeExtensionConfig() -> Bool {
        guard let url = extensionConfigURL else { return false }
        let payload: [String: String] = [
            PreferenceKey.theme: theme.id,
            PreferenceKey.quickLookMode: quickLookMode.rawValue,
        ]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Read side, used by the QuickLook extension.
    public static func extensionConfig() -> [String: String] {
        guard let url = extensionConfigURL,
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return object
    }

    public static func extensionTheme() -> Theme {
        Theme.named(extensionConfig()[PreferenceKey.theme] ?? Theme.fallback.id)
    }

    public static func extensionQuickLookMode() -> QuickLookMode {
        QuickLookMode(rawValue: extensionConfig()[PreferenceKey.quickLookMode] ?? "") ?? .rendered
    }
}
