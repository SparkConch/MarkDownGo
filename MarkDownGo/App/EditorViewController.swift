import AppKit
import MarkDownGoCore

/// Owns the window layout via a split view: outline sidebar, editor, preview. Modes are just split
/// items collapsing; the heavy lifting lives in the views themselves.
final class EditorViewController: NSSplitViewController, NSMenuItemValidation {
    enum Mode: Int { case source = 0, split = 1, wysiwyg = 2 }

    var modeDidChange: ((Mode) -> Void)?

    private(set) var mode: Mode = .split
    private let document: Document
    private let editorView = EditorTextView()
    private(set) var preview: PreviewView!
    private let outline = OutlineViewController()
    private let scrollView = NSScrollView()
    private var lastEditorScrollAt = Date.distantPast
    private var lastPreviewScrollAt = Date.distantPast
    private var previewItem: NSSplitViewItem?
    private var positioned = false
    private var probeScheduled = false

    init(document: Document) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        preview = PreviewPool.shared.take()
        editorView.setMarkdown(document.text)
        preview.update(markdown: document.text)
        reloadOutline()

        editorView.onChange = { [weak self] text in
            self?.document.editorDidChange(text)
            self?.scheduleRefresh(text)
        }
        editorView.documentURLProvider = { [weak self] in self?.document.fileURL }
        outline.onSelect = { [weak self] lineStart in
            self?.editorView.jump(toLineStart: lineStart)
        }

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = editorView
        let ruler = LineNumberRulerView(textView: editorView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = Preferences.lineNumbers
        editorView.ruler = ruler

        // Scroll binding: editor drives the preview, the preview drives the editor back.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(editorDidScroll(_:)),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
        preview.onScroll = { [weak self] section in
            guard let self, self.mode == .split else { return }
            guard Date().timeIntervalSince(self.lastEditorScrollAt) > Layout.scrollGuard else { return }
            self.lastPreviewScrollAt = Date()
            self.editorView.scrollToSection(section, headings: self.headings)
        }

        // Panes sit side by side: vertical divider, set before items are added.
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let sidebar = NSSplitViewItem(sidebarWithViewController: outline)
        sidebar.canCollapse = true
        sidebar.minimumThickness = 170
        sidebar.maximumThickness = 300
        sidebar.holdingPriority = NSLayoutConstraint.Priority(265)
        addSplitViewItem(sidebar)

        let editorItem = NSSplitViewItem(viewController: StaticViewController(view: scrollView))
        editorItem.minimumThickness = 300
        editorItem.holdingPriority = NSLayoutConstraint.Priority(250)
        addSplitViewItem(editorItem)

        let previewPane = NSSplitViewItem(viewController: StaticViewController(view: preview))
        previewPane.minimumThickness = Layout.previewMinThickness
        previewPane.holdingPriority = NSLayoutConstraint.Priority(249)
        addSplitViewItem(previewPane)
        previewItem = previewPane

        setMode(.split, animated: false)

        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged(_:)),
            name: Preferences.didChange, object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidLayout() {
        super.viewDidLayout()
        if ProcessInfo.processInfo.environment["MDG_SMOKE"] == "layout", !probeScheduled, view.bounds.width > 100 {
            probeScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                var out = "LAYOUT isVertical=\(self.splitView.isVertical) dividerCount=\(self.splitView.subviews.count)\n"
                for (index, subview) in self.splitView.subviews.enumerated() {
                    out += "  pane[\(index)] frame=\(subview.frame) type=\(type(of: subview))\n"
                }
                FileHandle.standardError.write(Data(out.utf8))
            }
        }
        if !positioned, view.bounds.width > 700 {
            positioned = true
            let width = view.bounds.width
            // Divider 0 ends the outline; divider 1 ends the editor (56% of the remainder).
            splitView.setPosition(Layout.outlineWidth, ofDividerAt: 0)
            splitView.setPosition(Layout.outlineWidth + (width - Layout.outlineWidth) * Layout.editorShare, ofDividerAt: 1)
        }
    }

    /// Document-driven replacement (revert / undo snapshots): swap the text, restyle everything.
    func replaceText(_ text: String) {
        editorView.setMarkdown(text)
        preview.update(markdown: text)
        reloadOutline()
    }

    // MARK: - Modes

    @objc func setModeSource(_ sender: Any?) { setMode(.source) }
    @objc func setModeSplit(_ sender: Any?) { setMode(.split) }
    @objc func setModeWysiwyg(_ sender: Any?) { setMode(.wysiwyg) }

    @objc func modeControlChanged(_ sender: NSSegmentedControl) {
        setMode(Mode(rawValue: sender.selectedSegment) ?? .split)
    }

    func setMode(_ newMode: Mode, animated: Bool = true) {
        let widthChanged = (mode == .split) != (newMode == .split)
        mode = newMode
        editorView.wysiwyg = (newMode == .wysiwyg)
        // `isCollapsed` and a synchronous `setPosition` both re-lay out every pane (~0.5 s on long
        // documents). Hide the preview and move the divider on the next turn instead, so the switch
        // paints immediately and the reflow happens after it.
        let showPreview = (newMode == .split)
        preview.isHidden = !showPreview
        previewItem?.maximumThickness = showPreview ? .greatestFiniteMagnitude : 0
        previewItem?.minimumThickness = showPreview ? Layout.previewMinThickness : 0
        // Moving the divider is the expensive part (~0.5 s: it re-lays out every pane). Do it after
        // the switch has been painted so the mode change itself feels immediate.
        let target = showPreview
            ? Layout.outlineWidth + (view.bounds.width - Layout.outlineWidth) * Layout.editorShare
            : view.bounds.width
        DispatchQueue.main.async { [weak self] in
            guard let self, self.mode == newMode, self.positioned else { return }
            self.splitView.setPosition(target, ofDividerAt: 1)
        }
        // Heading offsets only move when the editor's width moves; recomputing them lays out the
        // whole document, so keep the cache across source↔WYSIWYG switches.
        if widthChanged { editorView.invalidateHeadingTops() }
        modeDidChange?(newMode)
    }

    // MARK: - Live refresh

    private func scheduleRefresh(_ text: String) {
        debounce?.invalidate()
        debounce = Timer.scheduledTimer(withTimeInterval: Layout.previewDebounce, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.preview.update(markdown: text)
            self.reloadOutline()
        }
    }
    private var debounce: Timer?

    /// Heading list shared by the outline and the scroll mapping; recomputed only when text changes.
    private var headings: [Heading] = []

    private func reloadOutline() {
        headings = Outline.headings(in: editorView.string, styled: editorView.styled)
        editorView.invalidateHeadingTops()
        outline.reload(headings)
    }

    @objc private func preferencesChanged(_ note: Notification) {
        editorView.applyPreferences()
        preview.applyTheme()
        for case let scroll as NSScrollView in view.subviewsRecursive() where scroll.documentView === editorView {
            scroll.rulersVisible = Preferences.lineNumbers
        }
    }

    // MARK: - Scroll binding

    @objc private func editorDidScroll(_ note: Notification) {
        guard mode == .split else { return }
        guard Date().timeIntervalSince(lastPreviewScrollAt) > Layout.scrollGuard else { return }
        lastEditorScrollAt = Date()
        preview.scrollToSection(editorView.currentSection(headings: headings))
    }

    #if DEBUG
    /// MDG_SMOKE=scroll: prove the binding numerically (no screenshots needed).
    func debugScrollSmoke() {
        editorView.scrollToRatio(0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            self.preview.currentScrollRatio { ratio in
                FileHandle.standardError.write(Data("SMOKE scroll editor→preview expected≈0.50 got=\(String(format: "%.2f", ratio))\n".utf8))
                self.preview.debugSimulateUserScroll(to: 0.8)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    let back = self.editorView.scrollRatio
                    FileHandle.standardError.write(Data("SMOKE scroll preview→editor expected≈0.80 got=\(String(format: "%.2f", back))\n".utf8))
                }
            }
        }
    }

    /// MDG_SMOKE=align: measure heading alignment across the panes and mode-switch cost.
    /// Ratio-only syncing looks fine on uniform prose and drifts badly once a long code block
    /// makes the two panes' heights disagree, so assert on the heading, not on the ratio.
    func debugAlignSmoke() {
        func report(_ line: String) { FileHandle.standardError.write(Data((line + "\n").utf8)) }
        let headings = Outline.headings(in: editorView.string, styled: editorView.styled)
        guard let targetIndex = headings.firstIndex(where: { $0.title == "对齐目标" }) else {
            report("SMOKE align missing target"); return
        }
        let anchor = targetIndex + 1
        func editorY() -> CGFloat {
            guard let manager = editorView.layoutManager else { return 0 }
            let location = headings[targetIndex].lineStart
            manager.ensureLayout(forCharacterRange: NSRange(location: location, length: 1))
            let glyph = manager.glyphIndexForCharacter(at: location)
            return editorView.textContainerOrigin.y
                + manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
        }
        func measure(_ attempt: Int) {
            self.preview.scrollToRatio(0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.editorView.scrollToOffset(editorY())
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.preview.debugHeadingOffset(anchor) { offset in
                        if offset.isNaN, attempt < 8 {
                            measure(attempt + 1)
                            return
                        }
                        report("SMOKE align editor→preview heading offset=\(String(format: "%.0f", offset))pt")
                        for (from, to) in [(Mode.split, Mode.source), (.source, .split), (.source, .wysiwyg), (.wysiwyg, .split)] {
                            var samples: [Double] = []
                            for _ in 0..<3 {
                                self.setMode(from, animated: false)
                                self.view.layoutSubtreeIfNeeded()
                                let start = ProcessInfo.processInfo.systemUptime
                                self.setMode(to, animated: false)
                                self.view.layoutSubtreeIfNeeded()
                                samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                            }
                            report("SMOKE mode \(from)→\(to) median=\(String(format: "%.1f", samples.sorted()[1]))ms")
                        }
                    }
                }
            }
        }
        measure(0)
    }
    #endif

    // MARK: - Menu validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleOutline(_:)) {
            menuItem.state = splitViewItems.first { $0.canCollapse }?.isCollapsed == false ? .on : .off
        }
        return true
    }

    @objc func toggleOutline(_ sender: Any?) {
        if let sidebar = splitViewItems.first(where: { $0.canCollapse }) {
            sidebar.animator().isCollapsed = !sidebar.isCollapsed
        }
    }
}

/// A bare view host for split items — the layout logic lives in the views, the controller only
/// arranges them.
final class StaticViewController: NSViewController {
    init(view: NSView) {
        super.init(nibName: nil, bundle: nil)
        self.view = view
    }
    required init?(coder: NSCoder) { fatalError("not used") }
}

extension NSView {
    func subviewsRecursive() -> [NSView] {
        subviews + subviews.flatMap { $0.subviewsRecursive() }
    }
}
