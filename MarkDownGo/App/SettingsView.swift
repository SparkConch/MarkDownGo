import SwiftUI
import MarkDownGoCore

struct SettingsView: View {
    @AppStorage(PreferenceKey.fontSize) private var fontSize: Double = 15
    @AppStorage(PreferenceKey.softWrap) private var softWrap = true
    @AppStorage(PreferenceKey.lineNumbers) private var lineNumbers = true
    @AppStorage(PreferenceKey.imageMode) private var imageMode = ImageStore.Mode.directory.rawValue
    @AppStorage(PreferenceKey.language) private var language = InterfaceLanguage.system.rawValue
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearanceMode.system.rawValue
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
    }
}
