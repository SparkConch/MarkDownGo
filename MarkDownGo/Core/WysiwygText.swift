import Foundation

/// A Markdown document with its syntax marks gone: what a reader sees, not what an author types.
///
/// This is the third Finder-preview option. It keeps the same scanner the editor uses (`Styler`),
/// then removes what only matters while editing:
///
///  * heading `#`, emphasis `*`, quote `>`, fence ``` runs — dropped
///  * link `[text](url)` — reduced to `text` (the URL is editor furniture, not reading matter)
///  * YAML front matter — dropped, exactly like the rendered HTML preview
///  * list bullets become `•`, task boxes become `☐`/`☑` (an ordered number stays, it carries meaning)
///
/// Kept in the core module and free of AppKit on purpose: the extension turns these ranges into
/// attributes, and the tests can assert the text itself.
public struct WysiwygText {
    /// The document without syntax marks.
    public let string: String
    /// Style tokens remapped onto `string`; marker tokens are gone with the text they covered.
    public let tokens: [StyleToken]

    public static func make(from text: String, styled: StyledText) -> WysiwygText {
        let source = text as NSString
        var edits: [Edit] = []

        for lineTokens in styled.tokens {
            // A task line already carries a box; a bullet in front of it would read as two markers.
            let hasTask = lineTokens.contains { $0.kind == .taskMark }
            for token in lineTokens where needsEdit(token) {
                edits.append(Edit(range: token.range,
                                  replacement: replacement(for: token, in: source, hasTask: hasTask)))
            }
        }
        let frontMatter = FrontMatter.detect(in: text)
        if !frontMatter.isEmpty {
            edits.append(Edit(range: frontMatter.range, replacement: ""))
        }
        edits = merged(edits)

        // Rebuild the string segment by segment so the surviving text keeps its order.
        var out = ""
        var cursor = 0
        for edit in edits {
            if edit.range.location > cursor {
                out += source.substring(with: NSRange(location: cursor,
                                                      length: edit.range.location - cursor))
            }
            out += edit.replacement
            cursor = max(cursor, NSMaxRange(edit.range))
        }
        if cursor < source.length {
            out += source.substring(from: cursor)
        }

        let outLength = (out as NSString).length
        var tokens: [StyleToken] = []
        for lineTokens in styled.tokens {
            for token in lineTokens where !needsEdit(token) && token.kind != .frontMatter {
                let start = position(token.range.location, edits: edits)
                let end = position(NSMaxRange(token.range), edits: edits)
                guard end > start, start >= 0, end <= outLength else { continue }
                tokens.append(StyleToken(range: NSRange(location: start, length: end - start),
                                        kind: token.kind))
            }
        }
        return WysiwygText(string: out, tokens: tokens)
    }

    // MARK: - Edits

    private struct Edit {
        let range: NSRange
        let replacement: String
    }

    private static func needsEdit(_ token: StyleToken) -> Bool {
        switch token.kind {
        case .linkURL:
            return true
        default:
            return token.kind.isMarker
        }
    }

    private static func replacement(for token: StyleToken, in source: NSString, hasTask: Bool) -> String {
        let text = NSMaxRange(token.range) <= source.length
            ? source.substring(with: token.range)
            : ""
        switch token.kind {
        case .listMark:
            // "1." carries meaning, and a task line draws its own box — only bare bullets get a dot.
            if hasTask { return "" }
            return text.contains(where: \.isNumber) ? "" : "• "
        case .taskMark:
            let checked = text.lowercased().contains("x")
            return checked ? "☑ " : "☐ "
        default:
            return ""
        }
    }

    /// Overlapping edits would corrupt the offsets; keep the earliest and extend it.
    private static func merged(_ edits: [Edit]) -> [Edit] {
        let sorted = edits.filter { $0.range.length > 0 }.sorted { $0.range.location < $1.range.location }
        var result: [Edit] = []
        for edit in sorted {
            if let last = result.last, edit.range.location < NSMaxRange(last.range) {
                let end = max(NSMaxRange(last.range), NSMaxRange(edit.range))
                result[result.count - 1] = Edit(
                    range: NSRange(location: last.range.location, length: end - last.range.location),
                    replacement: last.replacement
                )
            } else {
                result.append(edit)
            }
        }
        return result
    }

    /// Where a source offset ends up once the edits are applied. A boundary inside an edit resolves
    /// to the edit's leading edge, so tokens never get positive length from deleted text.
    private static func position(_ location: Int, edits: [Edit]) -> Int {
        var shift = 0
        for edit in edits {
            if NSMaxRange(edit.range) <= location {
                shift += (edit.replacement as NSString).length - edit.range.length
            } else if edit.range.location < location {
                shift += -(location - edit.range.location)
                break
            } else {
                break
            }
        }
        return location + shift
    }
}
