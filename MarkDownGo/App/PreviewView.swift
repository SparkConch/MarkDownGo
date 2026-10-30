import WebKit
import MarkDownGoCore

/// The live preview: a WKWebView fed over `mdg-preview://`, updated in place (no reload flicker)
/// with the HTML cmark renders.
final class PreviewView: WKWebView, WKNavigationDelegate, WKScriptMessageHandler {
    /// Fired when the user scrolls the preview; carries its scroll ratio (0…1).
    var onScroll: ((Double) -> Void)?
    private let scheme: PreviewScheme
    private var ready = false
    private var pending: String?

    init() {
        let scheme = PreviewScheme()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(scheme, forURLScheme: PreviewScheme.scheme)
        self.scheme = scheme
        super.init(frame: .zero, configuration: configuration)
        navigationDelegate = self
        underPageBackgroundColor = .textBackgroundColor
        configuration.userContentController.add(self, name: "scroll")
        load(URLRequest(url: PreviewScheme.pageURL))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(markdown: String) {
        let html = Self.withHeadingAnchors(MarkdownToHTML.render(markdown))
        scheme.html = html
        pending = html
        if ready { inject(html) }
    }

    func scrollToRatio(_ ratio: Double) {
        guard ready else { return }
        evaluateJavaScript("suppressScrollReporting(180); scrollToRatio(\(ratio))", completionHandler: nil)
    }

    /// Test affordance: scroll without suppressing the report, i.e. behave like a user scroll.
    func debugSimulateUserScroll(to ratio: Double) {
        let clamped = min(1, max(0, ratio))
        evaluateJavaScript("window.scrollTo(0, \(clamped) * (document.documentElement.scrollHeight - window.innerHeight))", completionHandler: nil)
    }

    func currentScrollRatio(_ completion: @escaping (Double) -> Void) {
        evaluateJavaScript("currentScrollRatio()") { value, _ in
            completion((value as? NSNumber)?.doubleValue ?? 0)
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "scroll", let ratio = (message.body as? NSNumber)?.doubleValue else { return }
        onScroll?(ratio)
    }

    func scrollToHeading(_ ordinal: Int) {
        guard ready else { return }
        evaluateJavaScript("scrollToHeading(\(ordinal))", completionHandler: nil)
    }

    func reloadChrome() {
        ready = false
        load(URLRequest(url: PreviewScheme.pageURL))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        if let pending { inject(pending) }
    }

    private func inject(_ html: String) {
        evaluateJavaScript("render(\(Self.javaScriptString(html)))", completionHandler: nil)
    }

    /// Numbers headings in document order so the editor's caret→heading count maps to an anchor.
    static func withHeadingAnchors(_ html: String) -> String {
        let regex = try! NSRegularExpression(pattern: "<h([1-6])>")
        let ns = html as NSString
        var result = ""
        var location = 0
        var counter = 0
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: location, length: match.range.location - location))
            counter += 1
            result += "<h\(ns.substring(with: match.range(at: 1))) id=\"h-\(counter)\">"
            location = NSMaxRange(match.range)
        }
        result += ns.substring(from: location)
        return result
    }

    static func javaScriptString(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value], options: [])
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }
}
