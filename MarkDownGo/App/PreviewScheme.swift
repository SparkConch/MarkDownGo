import MarkDownGoCore
import WebKit

/// Serves the preview over a custom scheme so everything (KaTeX fonts included) loads offline from
/// the app bundle; no network access, ever.
final class PreviewScheme: NSObject, WKURLSchemeHandler {
    static let scheme = "mdg-preview"
    static let pageURL = URL(string: "mdg-preview://page/index.html")!
    /// The currently rendered document body; the shell page is this plus the fixed bootstrap.
    var html = ""
    /// Theme stylesheet injected into the shell at serve time.
    var themeCSS = Theme.fallback.css()
    /// Mermaid needs to know up front whether the paper is dark; CSS can't tell it.
    var isDarkTheme = false
    /// In the split pane the preview sits beside the editor, so its body padding is pulled in to
    /// match the editor's textContainerInset. QuickLook and other hosts keep the theme's page
    /// padding, which reads like a sheet of paper.
    var compactPadding = true

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        let path = url.path
        if path == "/" || path == "/index.html" {
            let page = Self.shellTemplate
                .replacingOccurrences(of: "{{THEME_CSS}}", with: themeCSS)
                .replacingOccurrences(of: "{{THEME_DARK}}", with: isDarkTheme ? "true" : "false")
                .replacingOccurrences(of: "{{PANE_CSS}}", with: compactPadding ? Self.paneCSS : "")
            respond(urlSchemeTask, url: url, data: Data(page.utf8), mime: "text/html")
            return
        }
        let prefix = "/vendor/"
        guard path.hasPrefix(prefix), let root = Bundle.main.resourceURL?.appendingPathComponent("preview/vendor", isDirectory: true) else {
            fail(urlSchemeTask)
            return
        }
        let file = root.appendingPathComponent(String(path.dropFirst(prefix.count))).standardizedFileURL
        guard file.path.hasPrefix(root.standardizedFileURL.path), let data = try? Data(contentsOf: file) else {
            fail(urlSchemeTask)
            return
        }
        respond(urlSchemeTask, url: url, data: data, mime: Self.mime(for: file.pathExtension))
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    // MARK: - Internals

    private func respond(_ task: WKURLSchemeTask, url: URL, data: Data, mime: String) {
        let response = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: mime.hasPrefix("text") ? "utf-8" : nil)
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: WKURLSchemeTask) {
        task.didFailWithError(NSError(domain: "mdg.preview", code: 404, userInfo: [NSLocalizedDescriptionKey: "resource not found"]))
    }

    private static func mime(for ext: String) -> String {
        switch ext {
        case "js": return "text/javascript"
        case "css": return "text/css"
        case "html": return "text/html"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        default: return "application/octet-stream"
        }
    }

    /// Split-pane override: keeps the preview's first line level with the editor's.
    static let paneCSS = "body { padding: 16px 18px 60px !important; }"

    /// The preview page. Visual styling is *not* here — `{{THEME_CSS}}` is replaced with the
    /// selected theme's stylesheet (Resources/Themes/layout.css + {id}.css), so the in-app preview
    /// and the Finder QuickLook preview render from exactly the same tokens. This shell only owns
    /// behaviour: KaTeX for `$…$`, Mermaid for ```mermaid fences.
    static let shellTemplate = """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    <link rel="stylesheet" href="/vendor/katex/katex.min.css">
    <script src="/vendor/katex/katex.min.js"></script>
    <script src="/vendor/katex/contrib/auto-render.min.js"></script>
    <script src="/vendor/mermaid/mermaid.min.js"></script>
    <style>{{THEME_CSS}}</style>
    <style>{{PANE_CSS}}</style>
    <script>window.__MDG_DARK__ = {{THEME_DARK}};</script>
    </head>
    <body>
    <div id="content"></div>
    <script>
    function convertMermaid(root) {
      root.querySelectorAll('pre > code.language-mermaid').forEach(function (code) {
        var div = document.createElement('div');
        div.className = 'mermaid';
        div.textContent = code.textContent;
        code.parentElement.replaceWith(div);
      });
    }
    window.render = function (html) {
      var root = document.getElementById('content');
      root.innerHTML = html;
      convertMermaid(root);
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
        mermaid.initialize({ startOnLoad: false, securityLevel: 'loose', theme: (document.querySelector('body') && getComputedStyle(document.body).backgroundColor.match(/rgba?\\((\\d+), ?(\\d+), ?(\\d+)/) || [0,255,255,255]).slice(1,4).reduce((a,b)=>a+parseInt(b),0) < 300 ? 'dark' : 'default' });
        mermaid.run({ querySelector: '.mermaid' });
      } catch (e) {}
    };
    // Scroll binding: the preview reports its own ratio and accepts the editor's ratio.
    window.scrollToRatio = function (f) {
      var max = document.documentElement.scrollHeight - window.innerHeight;
      if (max > 0) window.scrollTo(0, Math.max(0, Math.min(1, f)) * max);
    };
    window.currentScrollRatio = function () {
      var max = document.documentElement.scrollHeight - window.innerHeight;
      return max > 0 ? window.scrollY / max : 0;
    };
    var __suppressUntil = 0;
    window.suppressScrollReporting = function (ms) { __suppressUntil = Date.now() + ms; };
    window.addEventListener('scroll', function () {
      if (Date.now() < __suppressUntil) return;
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.scroll) {
        window.webkit.messageHandlers.scroll.postMessage(window.currentScrollRatio());
      }
    }, { passive: true });
    </script>
    </body>
    </html>
    """
}
