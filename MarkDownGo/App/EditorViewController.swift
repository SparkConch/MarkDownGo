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
        outline.reload(Outline.headings(in: editorView.string, styled: editorView.styled))

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
        preview.onScroll = { [weak self] ratio in
            guard let self, self.mode == .split else { return }
            guard Date().timeIntervalSince(self.lastEditorScrollAt) > Layout.scrollGuard else { return }
            self.lastPreviewScrollAt = Date()
            self.editorView.scrollToRatio(ratio)
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
        previewPane.minimumThickness = 260
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
        outline.reload(Outline.headings(in: editorView.string, styled: editorView.styled))
    }

    // MARK: - Modes

    @objc func setModeSource(_ sender: Any?) { setMode(.source) }
    @objc func setModeSplit(_ sender: Any?) { setMode(.split) }
    @objc func setModeWysiwyg(_ sender: Any?) { setMode(.wysiwyg) }

    @objc func modeControlChanged(_ sender: NSSegmentedControl) {
        setMode(Mode(rawValue: sender.selectedSegment) ?? .split)
    }

    func setMode(_ newMode: Mode, animated: Bool = true) {
        mode = newMode
        editorView.wysiwyg = (newMode == .wysiwyg)
        let collapsed = (newMode != .split)
        if animated {
            previewItem?.animator().isCollapsed = collapsed
        } else {
            previewItem?.isCollapsed = collapsed
        }
        if newMode == .split, positioned { splitView.setPosition(view.bounds.width * 0.55, ofDividerAt: 1) }
        modeDidChange?(newMode)
    }

    // MARK: - Live refresh

    private func scheduleRefresh(_ text: String) {
        debounce?.invalidate()
        debounce = Timer.scheduledTimer(withTimeInterval: Layout.previewDebounce, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.preview.update(markdown: text)
            self.outline.reload(Outline.headings(in: self.editorView.string, styled: self.editorView.styled))
        }
    }
    private var debounce: Timer?

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
        preview.scrollToRatio(editorView.scrollRatio)
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
