import AppKit
import MarkDownGoCore
import SwiftUI

/// Launcher shown at launch and whenever the last document window closes: open, create, recents.
/// Deliberately light on options — the app is one window away from writing.
struct HomeView: View {
    @State private var recents: [URL] = []
    @State private var hovered: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MarkDownGo")
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(Palette.ink)
            HStack(spacing: 10) {
                actionButton(L("home.open"), shortcut: "⌘O", filled: true, action: openPanel)
                actionButton(L("home.new"), shortcut: "⌘N", filled: false, action: newDocument)
            }
            .padding(.top, 22)

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
                .padding(.vertical, 20)

            Text(L("home.recent").uppercased())
                .font(.system(size: 10, weight: .medium))
                .tracking(0.9)
                .foregroundStyle(Palette.muted)

            if recents.isEmpty {
                Text(L("home.recent.empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted.opacity(0.85))
                    .padding(.top, 16)
            } else {
                VStack(spacing: 1) {
                    ForEach(recents, id: \.self) { fetchRow($0) }
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(width: 520, height: 456, alignment: .topLeading)
        .background(Palette.canvas)
        .onAppear(perform: reload)
    }

    // MARK: - Pieces

    private func actionButton(_ title: String, shortcut: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(shortcut).font(.system(size: 10, design: .monospaced)).opacity(0.5)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(filled ? Palette.canvas : Palette.ink)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(filled ? Palette.ink : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: filled ? 0 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fetchRow(_ url: URL) -> some View {
        Button { open(url) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text(url.deletingLastPathComponent().path)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text("MD")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Palette.hairline.opacity(0.45)))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovered == url ? Palette.hairline.opacity(0.35) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = url } else if hovered == url { hovered = nil }
        }
    }

    // MARK: - Actions

    private func reload() {
        recents = Array(NSDocumentController.shared.recentDocumentURLs.prefix(8))
    }

    /// Keeps the launcher visible when the panel is cancelled; the document window covers it otherwise.
    private func openPanel() {
        NSDocumentController.shared.openDocument(nil)
    }

    private func newDocument() {
        NSDocumentController.shared.newDocument(nil)
        closeLauncher()
    }

    private func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        closeLauncher()
    }

    private func closeLauncher() {
        NSApp.keyWindow?.performClose(nil)
    }
}

private enum Palette {
    /// Warm bone in light mode, warm near-black in dark — the same pair the icon uses.
    static let canvas = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.098, green: 0.096, blue: 0.090, alpha: 1)
            : NSColor(srgbRed: 0.973, green: 0.965, blue: 0.949, alpha: 1)
    })
    static let ink = Color(nsColor: .labelColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let hairline = Color(nsColor: .separatorColor)
}
