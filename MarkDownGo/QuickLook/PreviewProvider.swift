import AppKit
import MarkDownGoCore
import os
import Quartz
import WebKit

private let log = Logger(subsystem: "com.sparkconch.MarkDownGo.quicklook", category: "preview")

/// Finder preview for Markdown files.
///
/// Three rules, learned the hard way:
///  1. **Never show a blank panel.** Every failure path ends in visible text (error message, or the
///     raw source). A blank QuickLook window tells the user nothing and looks like a broken app.
///  2. **Read the file with a security-scoped bookmark.** A sandboxed extension only gets a
///     security-scoped URL from QuickLook; without `startAccessingSecurityScopedResource` the read
///     fails and the panel stays empty.
///  3. **Do not depend on a custom URL scheme inside the extension.** `WKURLSchemeHandler` behaves
///     inconsistently in an appex; loading the shell with `loadHTMLString(_:baseURL:)` pointed at
///     the bundle's resource directory keeps KaTeX/Mermaid/fonts working through plain file URLs,
///     which the sandbox allows for our own bundle.
final class PreviewProvider: NSViewController, QLPreviewingController {
    private var contentView: NSView?

    // MARK: - QLPreviewingController

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        // QuickLook hands us a security-scoped URL; reading without this returns nothing (empty
        // panel) even though the file plainly exists.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            log.notice("read failed: \(url.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            showMessage("MarkDownGo 无法读取这个文件\n\n\(error.localizedDescription)", monospaced: false)
            handler(nil)
            return
        }

        let encoding = TextEncoding.detect(data)
        let text = String(data: data, encoding: encoding.cfEncoding)
            ?? String(decoding: data, as: UTF8.self)
        let mode = Preferences.extensionQuickLookMode()
        let theme = Preferences.extensionTheme()
        log.notice("preview \(url.lastPathComponent, privacy: .public) mode=\(mode.rawValue, privacy: .public) theme=\(theme.id, privacy: .public) bytes=\(data.count)")

        switch mode {
        case .code:
            showSource(text, fileName: url.lastPathComponent)
        case .rendered:
            showRendered(text, theme: theme)
        }
        handler(nil)
    }

    // MARK: - Code mode

    private func showSource(_ text: String, fileName: String) {
        let scroll = NSScrollView()
        let textView = NSTextView()
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)

        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        install(scroll)
    }

    // MARK: - Rendered mode

    private func showRendered(_ text: String, theme: Theme) {
        let body = MarkdownToHTML.render(text)
        let css = theme.css(in: .main)
        let dark = (theme.id == "ye")

        // Base URL = our own Resources directory, so `preview/vendor/...` resolves to real files.
        let base = Bundle.main.resourceURL
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <link rel="stylesheet" href="preview/vendor/katex/katex.min.css">
        <script src="preview/vendor/katex/katex.min.js"></script>
        <script src="preview/vendor/katex/auto-render.min.js"></script>
        <script src="preview/vendor/mermaid/mermaid.min.js"></script>
        <style>\(css)</style>
        </head>
        <body>
        <main id="content">\(body)</main>
        <script>
        window.__MDG_DARK__ = \(dark ? "true" : "false");
        (function () {
          var root = document.getElementById('content');
          root.querySelectorAll('pre > code.language-mermaid').forEach(function (code) {
            var div = document.createElement('div');
            div.className = 'mermaid';
            div.textContent = code.textContent;
            code.parentElement.replaceWith(div);
          });
          try {
            renderMathInElement(root, {
              delimiters: [
                {left: '$$', right: '$$', display: true},
                {left: '\\\\[', right: '\\\\]', display: true},
                {left: '$', right: '$', display: false},
                {left: '\\\\(', right: '\\\\)', display: false}
              ],
              ignoredTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code', 'option']
            });
          } catch (e) {}
          try {
            mermaid.initialize({ startOnLoad: false, securityLevel: 'loose',
                                 theme: window.__MDG_DARK__ ? 'dark' : 'default' });
            mermaid.run({ querySelector: '.mermaid' });
          } catch (e) {}
        })();
        </script>
        </body>
        </html>
        """

        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.setValue(false, forKey: "drawsBackground")
        web.loadHTMLString(html, baseURL: base)
        install(web)
        log.notice("rendered html bytes=\(html.utf8.count) base=\(base?.lastPathComponent ?? "nil", privacy: .public)")
    }

    // MARK: - Fallback

    private func showMessage(_ message: String, monospaced: Bool) {
        let scroll = NSScrollView()
        let textView = NSTextView()
        textView.string = message
        textView.font = monospaced
            ? .monospacedSystemFont(ofSize: 12.5, weight: .regular)
            : .systemFont(ofSize: 13)
        textView.textColor = .secondaryLabelColor
        textView.isEditable = false
        textView.textContainerInset = NSSize(width: 20, height: 18)
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        install(scroll)
    }

    // MARK: - Hosting

    /// Auto Layout, not frames: the QuickLook host resizes this view after `preparePreviewOfFile`
    /// returns, and a frame captured earlier collapses to nothing (a blank panel).
    private func install(_ child: NSView) {
        contentView?.removeFromSuperview()
        child.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.topAnchor.constraint(equalTo: view.topAnchor),
            child.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        contentView = child
        // Hosts that ignore Auto Layout sizing fall back to this; without it some panels open at
        // zero height and look empty.
        preferredContentSize = NSSize(width: 820, height: 600)
        log.notice("installed \(String(describing: type(of: child)), privacy: .public) in \(NSStringFromRect(self.view.frame), privacy: .public)")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 600))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        view = container
    }
}