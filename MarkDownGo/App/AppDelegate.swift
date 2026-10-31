import AppKit
import MarkDownGoCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindow: NSWindow?
    private var homeWindow: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        NSApp.mainMenu = MainMenu.build()
        NotificationCenter.default.addObserver(
            self, selector: #selector(documentWindowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyAppearance()
        showHome(nil)
        // Warm the WebContent process right after the launcher is up; the first document then
        // starts its preview against a live process instead of paying process spawn latency.
        DispatchQueue.main.async { PreviewPool.shared.prewarm() }
        #if DEBUG
        runSmokeHook()
        #endif
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged(_:)),
            name: Preferences.didChange, object: nil
        )
    }

    @objc private func preferencesChanged(_ note: Notification) {
        applyAppearance()
    }

    /// One switch covers every window, the launcher, and the preview (WKWebView follows
    /// `prefers-color-scheme` from the app appearance).
    private func applyAppearance() {
        switch Preferences.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    #if DEBUG
    /// Verification hook, inert unless `MDG_SMOKE` is set (and compiled out of Release builds): creating and opening documents can only
    /// be proven by launching the real app, so keep one way to drive it from a terminal.
    private func runSmokeHook() {
        let environment = ProcessInfo.processInfo.environment
        switch environment["MDG_SMOKE"] {
        case "layout":
            DispatchQueue.main.asyncAfter(deadline: .now() + Layout.smokeLaunchDelay) {
                _ = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
            }
        case "scroll":
            DispatchQueue.main.asyncAfter(deadline: .now() + Layout.smokeLaunchDelay) {
                guard let document = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true),
                      let controller = document.windowControllers.first as? DocumentWindowController else { return }
                let long = (1...120).map { "## 标题 \($0)\n\n这是第 \($0) 段，用来验证源码与预览的滚动绑定。\n" }.joined(separator: "\n")
                controller.editor.replaceText(long)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { controller.editor.debugScrollSmoke() }
            }
        case "new":
            DispatchQueue.main.asyncAfter(deadline: .now() + Layout.smokeLaunchDelay) {
                do {
                    let document = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
                    FileHandle.standardError.write(Data("SMOKE new ok: \(document.displayName ?? "?")\n".utf8))
                } catch {
                    FileHandle.standardError.write(Data("SMOKE new failed: \(error)\n".utf8))
                }
            }
        case "open":
            guard let path = environment["MDG_SMOKE_FILE"] else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Layout.smokeLaunchDelay) {
                NSDocumentController.shared.openDocument(withContentsOf: URL(fileURLWithPath: path), display: true) { document, _, error in
                    let message = error.map { "SMOKE open failed: \($0)\n" } ?? "SMOKE open ok: \(document?.displayName ?? "?")\n"
                    FileHandle.standardError.write(Data(message.utf8))
                }
            }
        default:
            break
        }
    }
    #endif

    /// The launcher replaces the "untitled document on launch" habit (SPEC §4).
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showHome(nil) }
        return true
    }

    @objc func showHome(_ sender: Any?) {
        if homeWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: HomeView()))
            window.title = "MarkDownGo"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.center()
            homeWindow = window
        }
        homeWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = L("menu.settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Bring the launcher back only when a *document* window closed and nothing else is left.
    @objc private func documentWindowWillClose(_ note: Notification) {
        guard let window = note.object as? NSWindow,
              window.windowController is DocumentWindowController else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let others = NSApp.windows.contains {
                $0.isVisible && !($0 is NSPanel) && $0 !== self.homeWindow && $0 !== self.settingsWindow
            }
            if !others { self.showHome(nil) }
        }
    }
}
