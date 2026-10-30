import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Markdown → HTML for the preview pane. cmark-gfm does the work; the front matter block is dropped
/// before parsing so the YAML header never shows up in the preview (SPEC Q31).
public enum MarkdownToHTML {
    /// Raw HTML passes through (`CMARK_OPT_UNSAFE`): a preview of the user's own document should look
    /// like the document. Everything runs offline in a WebView the app owns.
    /// Footnotes are a cmark-gfm core parse option (CMARK_OPT_FOOTNOTES), not an extension.
    private static let options = CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES
    private static let extensions = ["table", "strikethrough", "tasklist", "autolink", "tagfilter"]

    public static func render(_ text: String) -> String {
        let frontMatter = FrontMatter.detect(in: text)
        let body = frontMatter.isEmpty ? text : (text as NSString).substring(from: frontMatter.range.length)

        cmark_gfm_core_extensions_ensure_registered()
        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }

        for name in extensions {
            if let syntax = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, syntax)
            }
        }

        var bytes = Array(body.utf8)
        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            cmark_parser_feed(parser, UnsafeRawPointer(base).assumingMemoryBound(to: CChar.self), buffer.count)
        }

        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }

        guard let rendered = cmark_render_html(document, options, cmark_parser_get_syntax_extensions(parser)) else {
            return ""
        }
        defer { free(rendered) }
        return String(cString: rendered)
    }
}
