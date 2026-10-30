import Foundation

public struct Heading: Equatable {
    public let level: Int
    public let title: String
    /// UTF-16 offset of the heading's line start.
    public let lineStart: Int
}

/// Heading extraction for the outline sidebar. Shares the scanner's token stream, so the outline never
/// disagrees with what the editor styled as a heading.
public enum Outline {
    public static func headings(in text: String) -> [Heading] {
        headings(in: text, styled: Styler.style(text))
    }

    public static func headings(in text: String, styled: StyledText) -> [Heading] {
        let ns = text as NSString
        var result: [Heading] = []
        result.reserveCapacity(8)
        for (index, tokens) in styled.tokens.enumerated() {
            let lineStart = styled.lines[index].location
            for token in tokens {
                guard case .headingText(let level) = token.kind else { continue }
                let title = ns.substring(with: token.range)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                guard !title.isEmpty else { continue }
                result.append(Heading(level: level, title: title, lineStart: lineStart))
                break
            }
        }
        return result
    }
}
