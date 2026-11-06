import AppKit
import MarkDownGoCore

/// Makes MarkDownGo the default handler for Markdown files, without sending the user into
/// Finder's Get Info panel.
///
/// Two things have to change, and they are separate:
///  1. **LaunchServices** decides which app a double-click opens — that is
///     `LSSetDefaultRoleHandlerForContentType`.
///  2. **The document type registration** decides whether `.md` even resolves to our type; it is
///     declared in Info.plist and registered by LaunchServices when the app is seen.
///
/// Nothing here is global in a destructive sense: both calls are per-user, suppressible, and the
/// previous handler is restored by macOS the moment the app is deleted.
enum DefaultHandler {
    /// UTI our app declares for Markdown documents (see Info.plist → UTExportedTypeDeclarations).
    static let markdownUTI = "net.daringfireball.markdown"

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.sparkconch.MarkDownGo"
    }

    /// True when *we* are the app that opens Markdown files.
    static var isCurrent: Bool {
        currentHandlerIdentifier == bundleIdentifier
    }

    /// LaunchServices keeps per-role entries; `.all` is what double-click and `open` resolve,
    /// so it is the only honest thing to read and write.
    static var currentHandlerIdentifier: String? {
        LSCopyDefaultRoleHandlerForContentType(markdownUTI as CFString, .all)?
            .takeRetainedValue() as String?
    }

    /// Which app currently owns Markdown files, for display in Settings.
    static var currentHandlerName: String {
        guard let identifier = currentHandlerIdentifier else {
            return NSLocalizedString("settings.defaultHandler.none", comment: "")
        }
        if identifier == bundleIdentifier {
            return "MarkDownGo"
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            return identifier
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    /// Point Markdown files at this app. Returns false when LaunchServices refuses.
    @discardableResult
    static func apply() -> Bool {
        let status = LSSetDefaultRoleHandlerForContentType(
            markdownUTI as CFString, .all, bundleIdentifier as CFString
        )
        guard status == 0 else {
            return false
        }
        // LaunchServices caches per-extension associations separately from the UTI; touching the
        // concrete extensions makes Finder's "Open With" list agree immediately.
        for fileExtension in ["md", "markdown", "mdown", "mkd", "mkdn"] {
            NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL,
                                                     toOpenFileAt: URL(fileURLWithPath: "/tmp/probe.\(fileExtension)"))
        }
        return true
    }
}
