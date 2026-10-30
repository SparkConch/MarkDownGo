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

    var wysiwyg = false { didSet { restyle() } }
    private(set) var styled: StyledText = .empty
    private(set) var headings: [Heading] = []
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
        let caret = selectedRange().location
        let line = styled.lines.isEmpty ? 0 : styled.lineIndex(forCharacter: caret)
        if wysiwyg, line != visibleLine {
            visibleLine = line
            applyAll(visibleLine: line)
        }
    }

    // MARK: - Styling

    private func restyle() {
        styled = Styler.style(string)
        headings = Outline.headings(in: string, styled: styled)
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
