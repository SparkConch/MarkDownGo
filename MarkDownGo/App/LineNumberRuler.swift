import AppKit
import MarkDownGoCore

/// Line numbers for the source lines the scanner found. Wrapped continuation lines deliberately get
/// no number: Markdown is edited by source line, not by visual line.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var lineStarts: [Int] = []

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 38
    }

    required init(coder: NSCoder) { fatalError("not used") }

    func update(lineStarts: [Int]) {
        self.lineStarts = lineStarts
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer,
              let scrollView = scrollView else { return }
        let visible = scrollView.contentView.bounds
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let anchor = convert(NSZeroPoint, from: textView)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        var index = lineIndex(forCharacter: charRange.location)
        while index < lineStarts.count {
            let start = lineStarts[index]
            if start >= NSMaxRange(charRange) { break }
            let glyph = layoutManager.glyphIndexForCharacter(at: min(start, max(0, (textView.string as NSString).length - 1)))
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = lineRect.minY + anchor.y + textView.textContainerInset.height
            let number = "\(index + 1)" as NSString
            let size = number.size(withAttributes: attributes)
            number.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: y), withAttributes: attributes)
            index += 1
        }
    }

    private func lineIndex(forCharacter index: Int) -> Int {
        guard !lineStarts.isEmpty else { return 0 }
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= index { low = mid } else { high = mid - 1 }
        }
        return low
    }
}
