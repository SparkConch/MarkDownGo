import Foundation

/// The `---` fenced YAML header at the very top of a document.
///
/// Front matter is detected but never parsed: v0.1 keeps it verbatim (SPEC Q31) and simply
/// excludes it from styling and HTML rendering.
public struct FrontMatter: Equatable {
    /// UTF-16 range of the whole block, both delimiters and their line breaks included.
    /// `.zero` when the document has no header.
    public let range: NSRange

    public static let none = FrontMatter(range: NSRange(location: 0, length: 0))

    public var isEmpty: Bool { range.length == 0 }

    /// The opening delimiter must be the first line; the block ends at `---`, `...`, or is not
    /// front matter at all when no closing delimiter exists (an unterminated `---` is a thematic
    /// break in CommonMark, so it must keep rendering as one).
    public static func detect(in text: String) -> FrontMatter {
        let ns = text as NSString
        guard ns.length >= 3 else { return .none }

        var start = 0, end = 0, contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: 0, length: 0))
        guard line(ns, start, contentsEnd) == "---" else { return .none }

        var location = end
        while location < ns.length {
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let content = line(ns, start, contentsEnd)
            if content == "---" || content == "..." {
                return FrontMatter(range: NSRange(location: 0, length: end))
            }
            location = end
        }
        return .none
    }

    private static func line(_ ns: NSString, _ start: Int, _ contentsEnd: Int) -> String {
        ns.substring(with: NSRange(location: start, length: contentsEnd - start))
            .trimmingCharacters(in: .whitespaces)
    }
}
