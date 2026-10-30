import Foundation

/// What a run of source text means. The editor turns these into attributes; in WYSIWYG mode every
/// `isMarker` kind is hidden outside the line holding the caret (SPEC Q24).
public enum StyleKind: Equatable {
    case frontMatter
    case horizontalRule
    case headingMark(Int)
    case headingText(Int)
    case quoteMark
    case quoteText
    case listMark
    case taskMark
    case fenceMark
    case codeBlock
    case codeSpan
    case strong, strongMark
    case emphasis, emphasisMark
    case strike, strikeMark
    case linkText, linkURL, linkMark
    case imageMark
    case urlText

    /// Syntax punctuation that WYSIWYG hides.
    public var isMarker: Bool {
        switch self {
        case .headingMark, .quoteMark, .listMark, .taskMark, .fenceMark,
             .strongMark, .emphasisMark, .strikeMark, .linkMark, .imageMark:
            return true
        case .frontMatter, .horizontalRule, .headingText, .quoteText, .codeBlock, .codeSpan,
             .strong, .emphasis, .strike, .linkText, .linkURL, .urlText:
            return false
        }
    }
}

public struct StyleToken: Equatable {
    public let range: NSRange
    public let kind: StyleKind
}

/// Tokens bucketed per source line, so the view can restyle one line (caret moves, typing) instead
/// of the whole document.
public struct StyledText {
    /// One entry per line, terminators excluded.
    public let lines: [NSRange]
    /// Parallel to `lines`.
    public let tokens: [[StyleToken]]

    public init(lines: [NSRange], tokens: [[StyleToken]]) {
        self.lines = lines
        self.tokens = tokens
    }

    public static let empty = StyledText(lines: [], tokens: [])

    /// Index of the line containing a UTF-16 offset; clamped to the document bounds.
    public func lineIndex(forCharacter index: Int) -> Int {
        guard !lines.isEmpty else { return 0 }
        var low = 0, high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].location <= index { low = mid } else { high = mid - 1 }
        }
        return low
    }

    public func lineIndex(forLineAtCharacter index: Int) -> Int { lineIndex(forCharacter: index) }
}

/// Line-oriented Markdown scanner. It is deliberately not an AST: styling only needs the block a
/// line lives in plus inline shapes within it, and a scanner keeps ranges exact for CJK text where
/// byte/column based source maps drift.
public enum Styler {
    public static func style(_ text: String) -> StyledText {
        let ns = text as NSString
        let source = split(ns)
        guard !source.isEmpty else { return .empty }

        var tokens: [[StyleToken]] = Array(repeating: [], count: source.count)
        let frontMatter = FrontMatter.detect(in: text)
        var fence: String?

        var i = 0
        while i < source.count {
            let line = source[i]
            let content = line.content
            let range = line.range

            if !frontMatter.isEmpty, NSMaxRange(range) <= frontMatter.range.length {
                append(&tokens, i, range, .frontMatter)
                i += 1
                continue
            }

            if let marker = fence {
                if content.trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
                    append(&tokens, i, range, .fenceMark)
                    fence = nil
                } else {
                    append(&tokens, i, range, .codeBlock)
                }
                i += 1
                continue
            }

            if let marker = fenceMarker(content) {
                fence = marker
                append(&tokens, i, range, .fenceMark)
                i += 1
                continue
            }

            if let heading = atxHeading(content) {
                append(&tokens, i, offset(range, heading.mark.location, heading.mark.length), .headingMark(heading.level))
                let textRange = offset(range, heading.text.location, heading.text.length)
                append(&tokens, i, textRange, .headingText(heading.level))
                inline(ns, range: textRange, line: i, into: &tokens)
                i += 1
                continue
            }

            if i + 1 < source.count, let level = setextLevel(content, next: source[i + 1].content) {
                append(&tokens, i, range, .headingText(level))
                inline(ns, range: range, line: i, into: &tokens)
                append(&tokens, i + 1, source[i + 1].range, .headingMark(level))
                i += 2
                continue
            }

            if isThematicBreak(content) {
                append(&tokens, i, range, .horizontalRule)
                i += 1
                continue
            }

            var cursor = 0
            if let quotes = blockQuotePrefix(content) {
                append(&tokens, i, offset(range, 0, quotes), .quoteMark)
                cursor = quotes
            }

            let rest = NSString(string: content).substring(from: cursor)
            if let marker = listPrefix(rest) {
                append(&tokens, i, offset(range, cursor, marker.length), .listMark)
                var textStart = cursor + marker.length
                if let task = taskPrefix(NSString(string: content).substring(from: textStart)) {
                    append(&tokens, i, offset(range, textStart, task), .taskMark)
                    textStart += task
                }
                let textRange = offset(range, textStart, range.length - textStart)
                if cursor > 0 { append(&tokens, i, textRange, .quoteText) }
                inline(ns, range: textRange, line: i, into: &tokens)
                i += 1
                continue
            }

            let textRange = offset(range, cursor, range.length - cursor)
            if cursor > 0 { append(&tokens, i, textRange, .quoteText) }
            inline(ns, range: textRange, line: i, into: &tokens)
            i += 1
        }

        return StyledText(lines: source.map(\.range), tokens: tokens)
    }

    // MARK: - Lines

    private struct SourceLine {
        let content: String
        let range: NSRange
    }

    private static func split(_ ns: NSString) -> [SourceLine] {
        var result: [SourceLine] = []
        var location = 0
        var start = 0, end = 0, contentsEnd = 0
        while location < ns.length {
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let range = NSRange(location: start, length: contentsEnd - start)
            result.append(SourceLine(content: ns.substring(with: range), range: range))
            location = end
        }
        return result
    }

    private static func append(_ tokens: inout [[StyleToken]], _ line: Int, _ range: NSRange, _ kind: StyleKind) {
        guard range.length > 0, line < tokens.count else { return }
        tokens[line].append(StyleToken(range: range, kind: kind))
    }

    private static func offset(_ line: NSRange, _ location: Int, _ length: Int) -> NSRange {
        NSRange(location: line.location + location, length: max(0, length))
    }

    // MARK: - Block shapes

    private static let atx = try! NSRegularExpression(pattern: "^ {0,3}(#{1,6})([ \\t]+|$)(.*)$")
    private static let setext = try! NSRegularExpression(pattern: "^ {0,3}(=+|-+)[ \\t]*$")
    private static let thematic = try! NSRegularExpression(pattern: "^ {0,3}(?:(?:\\*[ \\t]*){3,}|(?:-[ \\t]*){3,}|(?:_[ \\t]*){3,})$")
    private static let quote = try! NSRegularExpression(pattern: "^ {0,3}((?:>[ \\t]?)+)")
    private static let list = try! NSRegularExpression(pattern: "^([-*+]|\\d{1,9}[.)])([ \\t]+)")
    private static let task = try! NSRegularExpression(pattern: "^\\[[ xX]\\][ \\t]+")

    private static func fenceMarker(_ content: String) -> String? {
        let trimmed = content.drop(while: { $0 == " " })
        guard content.count - trimmed.count <= 3 else { return nil }
        for character in ["`", "~"] where trimmed.hasPrefix(String(repeating: character, count: 3)) {
            return String(trimmed.prefix(while: { $0 == Character(character) }))
        }
        return nil
    }

    private static func atxHeading(_ content: String) -> (level: Int, mark: NSRange, text: NSRange)? {
        guard let match = atx.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length)) else { return nil }
        let level = match.range(at: 1).length
        let mark = NSRange(location: 0, length: match.range(at: 2).location + match.range(at: 2).length)
        return (level, mark, match.range(at: 3))
    }

    /// Setext headings need the following line, and only apply when the text line is not itself a
    /// block starter (`#`, `>`, list, table pipe, indented code).
    private static func setextLevel(_ content: String, next: String) -> Int? {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, content.count - trimmed.count <= 3 else { return nil }
        guard !["#", ">", "-", "*", "+", "|", "`", "~"].contains(where: { trimmed.hasPrefix($0) }) else { return nil }
        guard let match = setext.firstMatch(in: next, range: NSRange(location: 0, length: (next as NSString).length)) else { return nil }
        return (next as NSString).substring(with: match.range(at: 1)).hasPrefix("=") ? 1 : 2
    }

    private static func isThematicBreak(_ content: String) -> Bool {
        thematic.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length)) != nil
    }

    private static func blockQuotePrefix(_ content: String) -> Int? {
        guard let match = quote.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length)) else { return nil }
        return match.range(at: 1).location + match.range(at: 1).length
    }

    private static func listPrefix(_ content: String) -> NSRange? {
        guard let match = list.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length)) else { return nil }
        return NSRange(location: 0, length: match.range(at: 1).length + match.range(at: 2).length)
    }

    private static func taskPrefix(_ content: String) -> Int? {
        guard let match = task.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length)) else { return nil }
        return match.range.length
    }

    // MARK: - Inline shapes

    private static let codeSpanRegex = try! NSRegularExpression(pattern: "(?<!`)(`{1,3})([^`\\n]+?)\\1(?!`)")
    private static let imageRegex = try! NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\(([^)]*)\\)")
    private static let linkRegex = try! NSRegularExpression(pattern: "(?<!!)\\[([^\\]]*)\\]\\(([^)]*)\\)")
    private static let autolinkRegex = try! NSRegularExpression(pattern: "<((?:https?://|mailto:)[^>\\s]+)>")
    private static let strongRegex = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let emphasisRegex = try! NSRegularExpression(pattern: "(?<!\\*)(\\*|_)(?=\\S)([^*_]+?)(?<=\\S)\\1(?!\\*)")
    private static let strikeRegex = try! NSRegularExpression(pattern: "~~(?=\\S)(.+?)(?<=\\S)~~")

    /// One flat pass with a claim mask: nested shapes inside emphasis are not styled separately.
    /// `shortcut: inline nesting inside emphasis, add a recursive inline pass when users report it`.
    private static func inline(_ ns: NSString, range: NSRange, line: Int, into tokens: inout [[StyleToken]]) {
        guard range.length > 0 else { return }
        let slice = ns.substring(with: range) as NSString
        let bounds = NSRange(location: 0, length: slice.length)
        var claimed = [Bool](repeating: false, count: slice.length)

        func claim(_ r: NSRange) -> Bool {
            guard r.location >= 0, NSMaxRange(r) <= claimed.count else { return false }
            for index in r.location..<NSMaxRange(r) where claimed[index] { return false }
            for index in r.location..<NSMaxRange(r) { claimed[index] = true }
            return true
        }

        func emit(_ local: NSRange, _ kind: StyleKind) {
            append(&tokens, line, NSRange(location: range.location + local.location, length: local.length), kind)
        }

        for match in codeSpanRegex.matches(in: slice as String, range: bounds) {
            let whole = match.range
            guard claim(whole) else { continue }
            let ticks = match.range(at: 1).length
            emit(NSRange(location: whole.location, length: ticks), .strongMark)
            emit(NSRange(location: whole.location + ticks, length: whole.length - ticks * 2), .codeSpan)
            emit(NSRange(location: NSMaxRange(whole) - ticks, length: ticks), .strongMark)
        }

        for match in imageRegex.matches(in: slice as String, range: bounds) {
            let whole = match.range
            guard claim(whole) else { continue }
            let alt = match.range(at: 1)
            let url = match.range(at: 2)
            emit(NSRange(location: whole.location, length: 2), .imageMark)
            emit(alt, .linkText)
            emit(NSRange(location: NSMaxRange(alt), length: url.location - NSMaxRange(alt)), .linkMark)
            emit(url, .linkURL)
            emit(NSRange(location: NSMaxRange(url), length: NSMaxRange(whole) - NSMaxRange(url)), .linkMark)
        }

        for match in linkRegex.matches(in: slice as String, range: bounds) {
            let whole = match.range
            guard claim(whole) else { continue }
            let text = match.range(at: 1)
            let url = match.range(at: 2)
            emit(NSRange(location: whole.location, length: text.location - whole.location), .linkMark)
            emit(text, .linkText)
            emit(NSRange(location: NSMaxRange(text), length: url.location - NSMaxRange(text)), .linkMark)
            emit(url, .linkURL)
            emit(NSRange(location: NSMaxRange(url), length: NSMaxRange(whole) - NSMaxRange(url)), .linkMark)
        }

        for match in autolinkRegex.matches(in: slice as String, range: bounds) {
            let whole = match.range
            guard claim(whole) else { continue }
            emit(NSRange(location: whole.location, length: 1), .linkMark)
            emit(match.range(at: 1), .urlText)
            emit(NSRange(location: NSMaxRange(whole) - 1, length: 1), .linkMark)
        }

        for match in strongRegex.matches(in: slice as String, range: bounds) {
            let whole = match.range
            guard claim(whole) else { continue }
            let marker = match.range(at: 1).length
            emit(NSRange(location: whole.location, length: marker), .strongMark)
            emit(match.range(at: 2), .strong)
            emit(NSRange(location: NSMaxRange(whole) - marker, length: marker), .strongMark)
        }

        for match in emphasisRegex.matches(in: slice as String, range: bounds) {
            let whole = match.range
            guard claim(whole) else { continue }
            let marker = match.range(at: 1).length
            emit(NSRange(location: whole.location, length: marker), .emphasisMark)
            emit(match.range(at: 2), .emphasis)
            emit(NSRange(location: NSMaxRange(whole) - marker, length: marker), .emphasisMark)
        }

        for match in strikeRegex.matches(in: slice as String, range: bounds) {
            let whole = match.range
            guard claim(whole) else { continue }
            emit(NSRange(location: whole.location, length: 2), .strikeMark)
            emit(match.range(at: 1), .strike)
            emit(NSRange(location: NSMaxRange(whole) - 2, length: 2), .strikeMark)
        }
    }
}
