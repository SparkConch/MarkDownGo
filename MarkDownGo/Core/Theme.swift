import AppKit
import Foundation

/// Reading themes. Deliberately three, not eight: each one is a different *paper*, not a different
/// hue slapped on the same layout (the mistake that makes theme lists feel like a colour picker).
/// The tokens live in Resources/Themes/{id}.css; layout.css holds the shared skeleton.
public struct Theme: Identifiable, Equatable {
    public let id: String
    public let displayName: String
    public let summary: String
    /// Sidebar/preview swatch, so the picker can show the paper without rendering a document.
    public let paperHex: String
    public let inkHex: String

    public static let all: [Theme] = [
        Theme(id: "xuan", displayName: "宣纸", summary: "暖骨白纸面 · 墨黑衬线标题",
              paperHex: "#FAF7F1", inkHex: "#1C1B18"),
        Theme(id: "zhu", displayName: "朱批", summary: "宣纸底 · 印章朱红批注",
              paperHex: "#FCFAF6", inkHex: "#A8342A"),
        Theme(id: "ye", displayName: "夜读", summary: "深炭底 · 米白正文",
              paperHex: "#17171B", inkHex: "#E9E5DB"),
    ]

    public static let fallback = all[0]

    public static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? fallback
    }

    /// CSS for this theme: layout skeleton first, then the theme's tokens.
    /// `bundle` lets the QuickLook extension resolve its own resources with the same code.
    public func css(in bundle: Bundle = .main) -> String {
        [Bundle.css("layout", in: bundle), Bundle.css(id, in: bundle)]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    /// Paper and ink as AppKit colours, for the native WYSIWYG preview.
    public var paperColor: NSColor { NSColor(hex: paperHex) ?? .textBackgroundColor }
    public var inkColor: NSColor { NSColor(hex: inkHex) ?? .labelColor }
}

extension Bundle {
    /// Themes are copied into every bundle that renders a preview (app and QuickLook extension),
    /// so both resolve them the same way instead of sharing files through a container.
    static func css(_ name: String, in bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: name, withExtension: "css", subdirectory: "Themes") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// How QuickLook should present a Markdown file in Finder's preview pane.
public enum QuickLookMode: String, CaseIterable {
    case rendered
    /// Native styled text: markers stripped, same scanner as the editor, no WebKit involved.
    case wysiwyg
    case code

    public var displayName: String {
        switch self {
        case .rendered: return NSLocalizedString("quicklook.mode.rendered", comment: "")
        case .wysiwyg: return NSLocalizedString("quicklook.mode.wysiwyg", comment: "")
        case .code: return NSLocalizedString("quicklook.mode.code", comment: "")
    }
}
}

extension NSColor {
    /// `#RRGGBB` → NSColor. Lives here so the app and the QuickLook extension share one parser.
    public convenience init?(hex: String) {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((number >> 16) & 0xFF) / 255,
                  green: CGFloat((number >> 8) & 0xFF) / 255,
                  blue: CGFloat(number & 0xFF) / 255,
                  alpha: 1)
    }
}
