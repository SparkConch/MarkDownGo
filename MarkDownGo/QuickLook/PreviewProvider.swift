import AppKit
import MarkDownGoCore
import os
import Quartz
import WebKit

private let log = Logger(subsystem: "com.sparkconch.MarkDownGo.quicklook", category: "preview")

/// Finder preview for Markdown files.
///
/// Four rules, each one cost a debugging session:
///  1. **Never show a blank panel.** Every failure path ends in visible text (error message, or the
///     raw source). A blank QuickLook window tells the user nothing and looks like a broken app.
///  2. **Read the file with a security-scoped URL.** A sandboxed extension only gets a
///     security-scoped URL from QuickLook; without `startAccessingSecurityScopedResource` the read
///     fails and the panel stays empty.
///  3. **Lay out with frames and autoresizing, not Auto Layout**, and give every scroll view its
///     frame *before* asking for `contentSize`. The host resizes this view after
///     `preparePreviewOfFile` returns, and a child sized from a zero-frame scroll view draws nothing.
///  4. **WebKit needs `com.apple.security.network.client`** even for local HTML — without it the web
///     view never commits a load inside the `quicklook-preview` sandbox and the panel stays blank
///     (see MarkDownGoQuickLook.entitlements).
final class PreviewProvider: NSViewController, QLPreviewingController {
    private var contentView: NSView?

    // MARK: - QLPreviewingController

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            log.notice("read failed: \(url.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            showMessage("MarkDownGo 无法读取这个文件\n\n\(error.localizedDescription)")
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
        case .rendered:
            showRendered(text, theme: theme)
        case .wysiwyg:
            showWysiwyg(text, theme: theme)
        case .code:
            showSource(text)
        }
        handler(nil)
    }

    // MARK: - Code mode

    private func showSource(_ text: String) {
        // Frame first: `contentSize` is meaningless until the scroll view has bounds.
        let scroll = NSScrollView(frame: view.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        let contentSize = scroll.contentSize
        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width,
                                                      height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scroll.documentView = textView
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

        let web = WKWebView(frame: view.bounds, configuration: WKWebViewConfiguration())
        web.autoresizingMask = [.width, .height]
        web.setValue(false, forKey: "drawsBackground")
        web.loadHTMLString(html, baseURL: base)
        install(web)
        log.notice("rendered html bytes=\(html.utf8.count) base=\(base?.lastPathComponent ?? "nil", privacy: .public)")
    }

    // MARK: - WYSIWYG mode

    /// Reading view: the editor's own scanner decides what is text and what is syntax, markers are
    /// removed (not just made invisible), and the theme's paper and ink carry the colour. No WebKit,
    /// so this opens instantly — but it also means no images, tables or math: those stay as text,
    /// exactly like the in-app ⌘3 mode (SPEC Q19).
    private func showWysiwyg(_ text: String, theme: Theme) {
        let content = WysiwygText.make(from: text, styled: Styler.style(text))
        let ink = theme.inkColor
        let paper = theme.paperColor
        let body = NSMutableParagraphStyle()
        body.lineSpacing = 4
        body.paragraphSpacing = 8

        let attributed = NSMutableAttributedString(
            string: content.string,
            attributes: [
                .font: NSFont.systemFont(ofSize: Self.bodySize),
                .foregroundColor: ink,
                .paragraphStyle: body,
            ]
        )
        for token in content.tokens {
            attributed.addAttributes(attributes(for: token.kind, ink: ink), range: token.range)
        }
        let scroll = NSScrollView(frame: view.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = paper

        let contentSize = scroll.contentSize
        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.textStorage?.setAttributedString(attributed)
        textView.backgroundColor = paper
        textView.drawsBackground = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 32, height: 28)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: contentSize.width,
                                                      height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scroll.documentView = textView
        install(scroll)
        log.notice("wysiwyg chars=\(content.string.count) shown=\(content.tokens.count)")
    }

    private static let bodySize: CGFloat = 16

    private func attributes(for kind: StyleKind,
                            ink: NSColor) -> [NSAttributedString.Key: Any] {
        let bold = NSFontManager.shared
        switch kind {
        case .headingText(let level):
            let sizes: [CGFloat] = [0, 26, 22, 19, 17, 16, 16]
            let size = (level >= 1 && level <= 6) ? sizes[level] : Self.bodySize
            return [.font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: ink]
        case .quoteText:
            return [.foregroundColor: ink.withAlphaComponent(0.72)]
        case .codeBlock, .codeSpan:
            return [.font: NSFont.monospacedSystemFont(ofSize: Self.bodySize - 1, weight: .regular),
                    .foregroundColor: ink.withAlphaComponent(0.85),
                    .backgroundColor: ink.withAlphaComponent(0.07)]
        case .strong:
            return [.font: bold.convert(NSFont.systemFont(ofSize: Self.bodySize), toHaveTrait: .boldFontMask)]
        case .emphasis:
            return [.font: bold.convert(NSFont.systemFont(ofSize: Self.bodySize), toHaveTrait: .italicFontMask)]
        case .strike:
            return [.foregroundColor: ink.withAlphaComponent(0.6),
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue]
        case .linkText, .urlText:
            return [.foregroundColor: NSColor.linkColor]
        case .horizontalRule:
            return [.foregroundColor: ink.withAlphaComponent(0.35)]
        default:
            return [:]
        }
    }
    // MARK: - Fallback

    private func showMessage(_ message: String) {
        let scroll = NSScrollView(frame: view.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        let contentSize = scroll.contentSize
        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.string = message
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .secondaryLabelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.isEditable = false
        textView.textContainerInset = NSSize(width: 20, height: 18)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scroll.documentView = textView
        install(scroll)
    }

    // MARK: - Hosting

    private func install(_ child: NSView) {
        contentView?.removeFromSuperview()
        child.frame = view.bounds
        child.autoresizingMask = [.width, .height]
        view.addSubview(child)
        contentView = child
        preferredContentSize = NSSize(width: 820, height: 600)
        let size = NSStringFromRect(view.bounds)
        log.notice("installed \(String(describing: type(of: child)), privacy: .public) in \(size, privacy: .public)")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 600))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        view = container
    }
}
