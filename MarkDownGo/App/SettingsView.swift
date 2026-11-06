import SwiftUI
import MarkDownGoCore

/// Two-tone chip showing a theme's paper and ink at a glance.
private struct ThemeSwatch: View {
    let theme: Theme

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color(nsColor: NSColor(hex: theme.paperHex) ?? .textBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color(nsColor: NSColor(hex: theme.inkHex) ?? .labelColor))
                    .frame(width: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .padding(2)
            }
            .frame(width: 26, height: 16)
    }
}

extension NSColor {
    /// `#RRGGBB` → NSColor, used only for theme swatches.
    convenience init?(hex: String) {
        var value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        value = ""
        self.init(srgbRed: CGFloat((number >> 16) & 0xFF) / 255,
                  green: CGFloat((number >> 8) & 0xFF) / 255,
                  blue: CGFloat(number & 0xFF) / 255,
                  alpha: 1)
    }
}

struct SettingsView: View {
    @AppStorage(PreferenceKey.fontSize) private var fontSize: Double = 15
    @AppStorage(PreferenceKey.softWrap) private var softWrap = true
    @AppStorage(PreferenceKey.lineNumbers) private var lineNumbers = true
    @AppStorage(PreferenceKey.imageMode) private var imageMode = ImageStore.Mode.directory.rawValue
    @AppStorage(PreferenceKey.language) private var language = InterfaceLanguage.system.rawValue
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(PreferenceKey.theme) private var theme = Theme.fallback.id
    @AppStorage(PreferenceKey.quickLookMode) private var quickLookMode = QuickLookMode.rendered.rawValue
    @State private var isDefaultHandler = DefaultHandler.isCurrent
    @State private var currentHandlerName = DefaultHandler.currentHandlerName
    @State private var revision = 0

    var body: some View {
        Form {
            HStack {
                Text(L("settings.fontSize"))
                Slider(value: $fontSize, in: 11...24, step: 1) { _ in Preferences.notifyChanged() }
                Text("\(Int(fontSize)) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
            Toggle(L("settings.softWrap"), isOn: $softWrap)
            Toggle(L("settings.lineNumbers"), isOn: $lineNumbers)
            Picker(L("settings.imageMode"), selection: $imageMode) {
                Text(L("settings.imageMode.directory")).tag(ImageStore.Mode.directory.rawValue)
                Text(L("settings.imageMode.base64")).tag(ImageStore.Mode.base64.rawValue)
            }
            // Reading theme drives both the in-app preview and the Finder preview.
            Picker(L("settings.theme"), selection: $theme) {
                ForEach(Theme.all) { item in
                    HStack(spacing: 8) {
                        ThemeSwatch(theme: item)
                        Text(item.displayName)
                    }
                    .tag(item.id)
                }
            }
            .onChange(of: theme) { _ in Preferences.notifyChanged() }
            Text(Theme.named(theme).summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Default app for .md: LaunchServices decides this, so it is a button rather than a
            // toggle — there is no "off" state to write, only "make it us" / "leave it alone".
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("settings.defaultHandler"))
                    Text(isDefaultHandler
                         ? L("settings.defaultHandler.isUs")
                         : String(format: L("settings.defaultHandler.current"), currentHandlerName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("settings.defaultHandler.make")) {
                    DefaultHandler.apply()
                    refreshHandlerState()
                }
                .disabled(isDefaultHandler)
            }

            Picker(L("settings.quickLook"), selection: $quickLookMode) {
                ForEach(QuickLookMode.allCases, id: \.rawValue) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .onChange(of: quickLookMode) { _ in Preferences.notifyChanged() }
            Text(L("settings.quickLook.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(L("settings.appearance"), selection: $appearance) {
                ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                    Text(L("settings.appearance.\(mode.rawValue)")).tag(mode.rawValue)
                }
            }
            .onChange(of: appearance) { _ in Preferences.notifyChanged() }
            Picker(L("settings.language"), selection: $language) {
                ForEach(InterfaceLanguage.allCases, id: \.rawValue) { item in
                    Text(L(item == .system ? "settings.language.system" : "settings.language.\(item.rawValue)"))
                        .tag(item.rawValue)
                }
            }
            .onChange(of: language) { newValue in
                // Applies live: the delegate rebuilds menus and refreshes every window.
                Preferences.applyLanguage(InterfaceLanguage(rawValue: newValue) ?? .system)
                Preferences.notifyChanged()
            }
        }
        .padding(24)
        .frame(width: 460)
        .id(revision)
        .onReceive(NotificationCenter.default.publisher(for: Preferences.didChange)) { _ in revision += 1 }
        .onChange(of: softWrap) { _ in Preferences.notifyChanged() }
        .onChange(of: lineNumbers) { _ in Preferences.notifyChanged() }
        .onChange(of: imageMode) { _ in Preferences.notifyChanged() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshHandlerState()
        }
    }

    /// Re-reads LaunchServices state, e.g. after the user changed the default elsewhere.
    private func refreshHandlerState() {
        isDefaultHandler = DefaultHandler.isCurrent
        currentHandlerName = DefaultHandler.currentHandlerName
    }
}
