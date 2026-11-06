import AppKit
import MarkDownGoCore
import os
import Quartz
import WebKit

private let log = Logger(subsystem: "com.sparkconch.MarkDownGo.quicklook", category: "preview")

/// Finder preview for Markdown files.
///
/// Follows the setting the app writes (`mdg.quickLookMode`): **rendered** draws the document the
/// way the app's preview pane does — same cmark pipeline, same theme stylesheet — while **code**
/// shows the source in a text view, which is also the fast path (no WebKit process to spin up when
/// someone is just arrowing through files in a folder).
///
/// Everything is resolved from this extension's own bundle: themes and the KaTeX/Mermaid assets are
/// copied into both hosts, so no App Group container or shared file is involved.
final class PreviewProvider: NSViewController, QLPreviewingController {
    private var webView: WKWebView?
    private var scheme: PreviewScheme?
    private let scrollView = NSScrollView()
    private let textView = NSTextView()

    // MARK: - QLPreviewingController

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let data = try Data(contentsOf: url)
            // Same encoding detection as the editor: a GB18030 file must not preview as mojibake.
            let encoding = TextEncoding.detect(data)
            let text = String(data: data, encoding: encoding.cfEncoding)
                ?? String(decoding: data, as: UTF8.self)

            let mode = Preferences.extensionQuickLookMode()
            log.debug("preview requested: \(url.lastPathComponent, privacy: .public) mode=\(mode.rawValue, privacy: .public) theme=\(Preferences.extensionTheme().id, privacy: .public) bytes=\(data.count)")
            switch mode {
            case .code:
                showCode(text)
            case .rendered:
                showRendered(text, theme: Preferences.extensionTheme())
            }
            handler(nil)
        } catch {
            handler(error)
        }
    }

    // MARK: - Modes

    private func showCode(_ text: String) {
        teardownWebView()
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = .textColor
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        installIfNeeded(scrollView)
    }

    private func showRendered(_ text: String, theme: Theme) {
        let scheme = PreviewScheme()
        scheme.themeCSS = theme.css(in: .main)
        scheme.isDarkTheme = (theme.id == "ye")
        // A QuickLook panel is a page, not a split pane: keep the theme's own page padding.
        scheme.compactPadding = false
        scheme.html = MarkdownToHTML.render(text)
        self.scheme = scheme

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(scheme, forURLScheme: PreviewScheme.scheme)
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.underPageBackgroundColor = NSColor(srgbRed: 0.98, green: 0.97, blue: 0.95, alpha: 1)
        web.navigationDelegate = self
        webView = web
        web.load(URLRequest(url: PreviewScheme.pageURL))
        installIfNeeded(web)
    }

    private func teardownWebView() {
        webView?.removeFromSuperview()
        webView = nil
        scheme = nil
    }

    private func installIfNeeded(_ view: NSView) {
        for subview in self.view.subviews { subview.removeFromSuperview() }
        view.frame = self.view.bounds
        view.autoresizingMask = [.width, .height]
        self.view.addSubview(view)
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 560))
    }
}

extension PreviewProvider: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let html = scheme?.html else { return }
        let payload = (try? JSONSerialization.data(withJSONObject: [html], options: []))
            .flatMap { String(data: $0, encoding: .utf8) }
            .map { String($0.dropFirst().dropLast()) } ?? "\"\""
        webView.evaluateJavaScript("render(\(payload))", completionHandler: nil)
    }
}
