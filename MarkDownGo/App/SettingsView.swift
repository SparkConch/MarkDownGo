import SwiftUI
import MarkDownGoCore

struct SettingsView: View {
    @AppStorage(PreferenceKey.fontSize) private var fontSize: Double = 15
    @AppStorage(PreferenceKey.softWrap) private var softWrap = true
    @AppStorage(PreferenceKey.lineNumbers) private var lineNumbers = true
    @AppStorage(PreferenceKey.imageMode) private var imageMode = ImageStore.Mode.directory.rawValue
    @AppStorage(PreferenceKey.language) private var language = InterfaceLanguage.system.rawValue
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearanceMode.system.rawValue

    var body: some View {
        Form {
            HStack {
                Text("settings.fontSize")
                Slider(value: $fontSize, in: 11...24, step: 1) { _ in Preferences.notifyChanged() }
                Text("\(Int(fontSize)) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
            Toggle("settings.softWrap", isOn: $softWrap)
            Toggle("settings.lineNumbers", isOn: $lineNumbers)
            Picker("settings.imageMode", selection: $imageMode) {
                Text("settings.imageMode.directory").tag(ImageStore.Mode.directory.rawValue)
                Text("settings.imageMode.base64").tag(ImageStore.Mode.base64.rawValue)
            }
            Picker("settings.appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .onChange(of: appearance) { _ in Preferences.notifyChanged() }
            Picker("settings.language", selection: $language) {
                ForEach(InterfaceLanguage.allCases, id: \.rawValue) { language in
                    Text(language.displayName).tag(language.rawValue)
                }
            }
            .onChange(of: language) { newValue in
                if Preferences.applyLanguage(InterfaceLanguage(rawValue: newValue) ?? .system) {
                    let alert = NSAlert()
                    alert.messageText = L("settings.restart.title")
                    alert.informativeText = L("settings.restart.body")
                    alert.runModal()
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .onChange(of: softWrap) { _ in Preferences.notifyChanged() }
        .onChange(of: lineNumbers) { _ in Preferences.notifyChanged() }
        .onChange(of: imageMode) { _ in Preferences.notifyChanged() }
    }
}
