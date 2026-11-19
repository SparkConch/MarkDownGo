import AppKit
import MarkDownGoCore

/// The source editor. One NSTextView for all three modes; WYSIWYG only changes attributes (markers
/// become invisible ink outside the caret's line, SPEC Q24).
///
/// TextKit 1 on purpose: attribute edits go through `textStorage`, and touching `textStorage` on a
/// TextKit 2 view downgrades it to TK1 anyway — explicit beats silent (SPEC §3).
final class EditorTextView: NSTextView, NSTextViewDelegate {
    var onChange: ((String) -> Void)?
    var documentURLProvider: (() -> URL?)?
    weak var ruler: LineNumberRulerView?

    var wysiwyg = false {
        didSet {
            guard wysiwyg != oldValue else { return }
            let previousLine = visibleLine
            visibleLine = wysiwyg ? (styled.lines.isEmpty ? 0 : styled.lineIndex(forCharacter: selectedRange().location)) : -1
            applyMarkers(on: styled.tokens.indices, visibleLine: visibleLine)
            if previousLine >= 0 { applyMarkers(on: [previousLine], visibleLine: visibleLine) }
        }
    }
    private(set) var styled: StyledText = .empty
    private var visibleLine = -1
    private let imageStore = ImageStore()
    private let bodyStyle: NSMutableParagraphStyle

    /// NSTextView's designated initializer — the one AppKit routes `init(frame:)` through. Anything
    /// else leaves the class half-initialised and crashes on first use.
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = 6
        bodyStyle = style
        super.init(frame: frameRect, textContainer: container)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Explicit TextKit 1 text system: storage → layout manager → container that tracks the width.
    convenience init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        self.init(frame: NSRect(x: 0, y: 0, width: 640, height: 480), textContainer: container)
    }

    private func setup() {
        delegate = self
        allowsUndo = true
        isRichText = false
        importsGraphics = false
        usesFindBar = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        smartInsertDeleteEnabled = false
        textContainerInset = NSSize(width: 18, height: 16)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        applyPreferences()
    }

    func applyPreferences() {
        let widthTracks = Preferences.softWrap
        textContainer?.widthTracksTextView = widthTracks
        isHorizontallyResizable = !widthTracks
        needsDisplay = true
        restyle()
    }

    func setMarkdown(_ text: String) {
        string = text
        restyle()
    }

    // MARK: - Change pipeline

    override func didChangeText() {
        super.didChangeText()
        restyle()
        onChange?(string)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard wysiwyg else { return }
        let previousLine = visibleLine
        let line = styled.lines.isEmpty ? 0 : styled.lineIndex(forCharacter: selectedRange().location)
        guard line != previousLine else { return }
        visibleLine = line
        applyMarkers(on: [previousLine, line], visibleLine: line)
    }

    // MARK: - Styling

    private func restyle() {
        invalidateHeadingTops()
        styled = Styler.style(string)
        let caret = selectedRange().location
        visibleLine = wysiwyg ? (styled.lines.isEmpty ? 0 : styled.lineIndex(forCharacter: caret)) : -1
        applyAll(visibleLine: visibleLine)
        ruler?.update(lineStarts: styled.lines.map(\.location))
    }

    /// Full-document pass. The scanner is one line loop, so per-keystroke restyling stays cheap for
    /// the document sizes this editor targets.
    /// `shortcut: no incremental restyle, measure with real 1 MB documents before adding one`.
    private func applyAll(visibleLine: Int) {
        guard let storage = textStorage else { return }
        let undo = undoManager
        undo?.disableUndoRegistration()
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))
        for index in styled.tokens.indices {
            let visible = (index == visibleLine)
            for token in styled.tokens[index] { apply(token, visible: visible) }
        }
        storage.endEditing()
        undo?.enableUndoRegistration()
        needsDisplay = true
    }

    /// Mode switches and caret moves only change marker visibility; text-token styling is stable,
    /// so re-running the whole document here was the visible stall when switching modes.
    private func applyMarkers<S: Sequence>(on lines: S, visibleLine: Int) where S.Element == Int {
        guard let storage = textStorage else { return }
        let undo = undoManager
        undo?.disableUndoRegistration()
        storage.beginEditing()
        var seen = Set<Int>()
        for index in lines where styled.tokens.indices.contains(index) && seen.insert(index).inserted {
            for token in styled.tokens[index] where token.kind.isMarker {
                apply(token, visible: index == visibleLine)
            }
        }
        storage.endEditing()
        undo?.enableUndoRegistration()
        needsDisplay = true
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.textColor, .paragraphStyle: bodyStyle]
    }

    private var fontSize: CGFloat { CGFloat(Preferences.fontSize) }

    private func apply(_ token: StyleToken, visible: Bool) {
        guard let storage = textStorage, let manager = NSFontManager.shared as NSFontManager? else { return }
        let hide = wysiwyg && token.kind.isMarker && !visible
        var attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: bodyStyle, .foregroundColor: NSColor.textColor]
        var font = NSFont.systemFont(ofSize: fontSize)

        switch token.kind {
        case .headingMark(let level):
            font = headingFont(level).withSize(max(headingFont(level).pointSize * 0.55, 1))
            attributes[.foregroundColor] = NSColor.systemGray
        case .headingText(let level):
            font = headingFont(level)
            attributes[.foregroundColor] = headingColor(level)
        case .quoteMark:
            attributes[.foregroundColor] = NSColor.systemGray
        case .quoteText:
            attributes[.foregroundColor] = NSColor.secondaryLabelColor
        case .listMark, .taskMark, .fenceMark:
            attributes[.foregroundColor] = NSColor.systemGray
        case .codeBlock, .codeSpan:
            font = NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
            attributes[.foregroundColor] = NSColor.systemTeal
            attributes[.backgroundColor] = NSColor.quaternaryLabelColor
        case .strong, .strongMark:
            font = manager.convert(NSFont.systemFont(ofSize: fontSize), toHaveTrait: .boldFontMask)
            attributes[.foregroundColor] = token.kind == .strong ? NSColor.textColor : NSColor.systemGray
        case .emphasis, .emphasisMark:
            font = manager.convert(NSFont.systemFont(ofSize: fontSize), toHaveTrait: .italicFontMask)
            attributes[.foregroundColor] = token.kind == .emphasis ? NSColor.textColor : NSColor.systemGray
        case .strike, .strikeMark:
            attributes[.foregroundColor] = token.kind == .strike ? NSColor.secondaryLabelColor : NSColor.systemGray
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        case .linkText, .urlText:
            attributes[.foregroundColor] = NSColor.controlAccentColor
        case .linkURL:
            font = NSFont.systemFont(ofSize: max(fontSize - 2, 9))
            attributes[.foregroundColor] = NSColor.systemGray
        case .linkMark, .imageMark:
            attributes[.foregroundColor] = NSColor.systemGray
        case .frontMatter:
            font = NSFont.monospacedSystemFont(ofSize: max(fontSize - 2, 9), weight: .regular)
            attributes[.foregroundColor] = NSColor.systemGray
        case .horizontalRule:
            attributes[.foregroundColor] = NSColor.systemGray
        }

        if hide {
            attributes[.foregroundColor] = NSColor.clear
            font = NSFont.systemFont(ofSize: 0.1)
        }
        attributes[.font] = font
        storage.setAttributes(attributes, range: token.range)
    }

    private func headingFont(_ level: Int) -> NSFont {
        let sizes: [CGFloat] = [0, 26, 22, 19, 17, 15, 15]
        let size = (level >= 1 && level <= 6) ? sizes[level] : 15
        return NSFont.boldSystemFont(ofSize: size + (fontSize - 15))
    }

    private func headingColor(_ level: Int) -> NSColor {
        switch level {
        case 1: return .controlAccentColor
        case 2: return .systemBlue
        case 3: return .systemIndigo
        case 4: return .systemTeal
        default: return .secondaryLabelColor
        }
    }

    // MARK: - Scroll ratio (bound to the preview)

    var scrollRatio: Double {
        guard let scroll = enclosingScrollView, let documentView = scroll.documentView else { return 0 }
        let maxOffset = documentView.bounds.height - scroll.contentView.bounds.height
        guard maxOffset > 1 else { return 0 }
        return min(1, max(0, scroll.contentView.bounds.origin.y / maxOffset))
    }

    func scrollToRatio(_ ratio: Double) {
        guard let scroll = enclosingScrollView, let documentView = scroll.documentView else { return }
        let maxOffset = documentView.bounds.height - scroll.contentView.bounds.height
        guard maxOffset > 0 else { return }
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.origin.x,
                                             y: min(maxOffset, max(0, ratio) * maxOffset)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func scrollToOffset(_ y: CGFloat) {
        guard let scroll = enclosingScrollView, let documentView = scroll.documentView else { return }
        let maxOffset = max(0, documentView.bounds.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.origin.x,
                                             y: min(maxOffset, max(0, y))))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    // MARK: - Section mapping (shared vocabulary with the preview's heading anchors)

    /// Y offset of a source position, laid out on demand so it is correct before first display.
    func offsetY(forCharacter location: Int) -> CGFloat {
        guard let manager = layoutManager else { return 0 }
        let clamped = min(max(0, location), max(0, (string as NSString).length - 1))
        manager.ensureLayout(forCharacterRange: NSRange(location: clamped, length: 1))
        let glyph = manager.glyphIndexForCharacter(at: clamped)
        return textContainerOrigin.y + manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
    }

    /// Heading offsets are cached per text revision: computing them lays out the document, and
    /// doing that on every scroll event is what made entering split view stall.
    private var headingTops: [CGFloat] = []
    private var headingTopsKey: Int = -1

    private func tops(for headings: [Heading]) -> [CGFloat] {
        let key = headings.count &* 31 &+ (string as NSString).length
        if key != headingTopsKey || headingTops.count != headings.count {
            headingTops = headings.map { offsetY(forCharacter: $0.lineStart) }
            headingTopsKey = key
        }
        return headingTops
    }

    func invalidateHeadingTops() { headingTopsKey = -1 }

    /// Where the viewport top sits, expressed against `headings` (same order as the preview's anchors).
    func currentSection(headings: [Heading]) -> PreviewView.Section {
        guard let scroll = enclosingScrollView else { return PreviewView.Section(index: 0, fraction: 0) }
        let y = scroll.contentView.bounds.origin.y
        let tops = tops(for: headings)
        let documentHeight = scroll.documentView?.bounds.height ?? 0
        guard !tops.isEmpty else {
            let maxOffset = max(1, documentHeight - scroll.contentView.bounds.height)
            return PreviewView.Section(index: 0, fraction: Double(min(1, max(0, y / maxOffset))))
        }
        var index = 0
        while index + 1 < tops.count && tops[index + 1] <= y { index += 1 }
        let end = index + 1 < tops.count ? tops[index + 1] : documentHeight
        let span = max(1, end - tops[index])
        return PreviewView.Section(index: index, fraction: Double(min(1, max(0, (y - tops[index]) / span))))
    }

    func scrollToSection(_ section: PreviewView.Section, headings: [Heading]) {
        guard let scroll = enclosingScrollView else { return }
        let tops = tops(for: headings)
        let fraction = CGFloat(min(1, max(0, section.fraction)))
        let documentHeight = scroll.documentView?.bounds.height ?? 0
        let y: CGFloat
        if tops.isEmpty {
            y = fraction * max(0, documentHeight - scroll.contentView.bounds.height)
        } else {
            let index = min(max(0, section.index), tops.count - 1)
            let end = index + 1 < tops.count ? tops[index + 1] : documentHeight
            y = tops[index] + fraction * max(0, end - tops[index])
        }
        scrollToOffset(y)
    }

    // MARK: - Navigation

    func jump(toLineStart location: Int) {
        let length = (string as NSString).length
        let target = min(max(0, location), length)
        setSelectedRange(NSRange(location: target, length: 0))
        scrollRangeToVisible(NSRange(location: target, length: min(1, max(0, length - target))))
        window?.makeFirstResponder(self)
    }

    // MARK: - Images

    override func paste(_ sender: Any?) {
        if insertImage(from: NSPasteboard.general, type: .png) || insertImage(from: NSPasteboard.general, type: .tiff) {
            return
        }
        super.paste(sender)
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if type == .fileURL, insertImageFile(from: pboard) { return true }
        return super.readSelection(from: pboard, type: type)
    }

    private func insertImage(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let data = pasteboard.data(forType: type), let image = NSImage(data: data) else { return false }
        let png = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:]) ?? data
        return insertImageData(png, fileExtension: ImageStore.fileExtension(for: png))
    }

    private func insertImageFile(from pasteboard: NSPasteboard) -> Bool {
        guard let value = pasteboard.propertyList(forType: .fileURL) as? String,
              let url = URL(string: value),
              ["png", "jpg", "jpeg", "gif", "webp"].contains(url.pathExtension.lowercased()),
              let data = try? Data(contentsOf: url) else { return false }
        return insertImageData(data, fileExtension: ImageStore.fileExtension(for: data))
    }

    private func insertImageData(_ data: Data, fileExtension: String) -> Bool {
        do {
            let markdown = try imageStore.markdown(
                for: data,
                fileExtension: fileExtension,
                documentURL: documentURLProvider?(),
                mode: Preferences.imageMode
            )
            insertText(markdown, replacementRange: selectedRange())
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }
}
