import WebKit

/// Serves the preview over a custom scheme so everything (KaTeX fonts included) loads offline from
/// the app bundle; no network access, ever.
final class PreviewScheme: NSObject, WKURLSchemeHandler {
    static let scheme = "mdg-preview"
    static let pageURL = URL(string: "mdg-preview://page/index.html")!
    /// The currently rendered document body; the shell page is this plus the fixed bootstrap.
    var html = ""

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        let path = url.path
        if path == "/" || path == "/index.html" {
            respond(urlSchemeTask, url: url, data: Data(Self.shell.utf8), mime: "text/html")
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

    /// The preview page: styles follow the system appearance, KaTeX renders `$…$`/`$$…$$`, and
    /// ```mermaid fences become diagrams.
    private static let shell = """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    <link rel="stylesheet" href="/vendor/katex/katex.min.css">
    <script src="/vendor/katex/katex.min.js"></script>
    <script src="/vendor/katex/contrib/auto-render.min.js"></script>
    <script src="/vendor/mermaid/mermaid.min.js"></script>
    <style>
      :root { color-scheme: light dark; }
      /* Padding matches the editor's textContainerInset (18 horizontal / 16 vertical) so the two
         panes start on the same line instead of a few points apart. */
      body { margin: 0; padding: 16px 18px 60px; font: 15px/1.65 -apple-system, "PingFang SC", "Helvetica Neue", sans-serif;
             color: canvas-text; background: canvas; word-wrap: break-word; }
      h1,h2 { border-bottom: 1px solid color-mix(in srgb, canvas-text 12%, transparent); padding-bottom: .3em; }
      h1 { font-size: 1.9em; } h2 { font-size: 1.5em; } h3 { font-size: 1.25em; }
      a { color: #2563eb; text-decoration: none; } a:hover { text-decoration: underline; }
      code { font: 87% ui-monospace, SFMono-Regular, Menlo, monospace; background: color-mix(in srgb, canvas-text 8%, transparent);
             padding: .15em .35em; border-radius: 5px; }
      pre { background: color-mix(in srgb, canvas-text 6%, transparent); border: 1px solid color-mix(in srgb, canvas-text 10%, transparent);
            border-radius: 8px; padding: 12px 14px; overflow: auto; }
      pre code { background: none; padding: 0; }
      blockquote { margin: 0; padding: 2px 16px; border-left: 4px solid color-mix(in srgb, canvas-text 20%, transparent);
                   color: color-mix(in srgb, canvas-text 70%, transparent); }
      table { border-collapse: collapse; } th, td { border: 1px solid color-mix(in srgb, canvas-text 18%, transparent);
             padding: 6px 12px; } th { background: color-mix(in srgb, canvas-text 6%, transparent); }
      img { max-width: 100%; }
      hr { border: none; border-top: 2px solid color-mix(in srgb, canvas-text 12%, transparent); }
      .task-list-item { list-style: none; margin-left: -1.2em; }
      .footnotes { color: color-mix(in srgb, canvas-text 60%, transparent); font-size: .9em; }
      .mermaid { background: canvas; }
    </style>
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
        mermaid.initialize({ startOnLoad: false, securityLevel: 'loose', theme: matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default' });
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
    window.scrollToHeading = function (n) {
      var el = document.getElementById('h-' + n);
      if (el) window.scrollTo({ top: el.getBoundingClientRect().top + window.scrollY - 28, behavior: 'smooth' });
    };
    </script>
    </body>
    </html>
    """
}
