import AppKit

final class DocumentWindowController: NSWindowController, NSToolbarDelegate {
    let editor: EditorViewController

    private let modeIdentifier = NSToolbarItem.Identifier("mdg.mode")
    private let outlineIdentifier = NSToolbarItem.Identifier("mdg.outline")
    private weak var modeControl: NSSegmentedControl?

    init(document: Document) {
        editor = EditorViewController(document: document)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Layout.windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = Layout.windowMinSize
        super.init(window: window)
        // `document` is set by NSDocument.addWindowController — setting it here first makes that
        // call a no-op and the document ends up with zero window controllers (window never shows).
        window.contentViewController = editor
        // Assigning a contentViewController lets the view's fitting size win over contentRect;
        // pin the size back or the window collapses to the panes' minimum thicknesses.
        window.setContentSize(Layout.windowSize)
        editor.modeDidChange = { [weak self] mode in self?.modeControl?.selectedSegment = mode.rawValue }

        let toolbar = NSToolbar(identifier: "mdg.main")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbarStyle = .unified
        window.toolbar = toolbar
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [modeIdentifier, .flexibleSpace, outlineIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [modeIdentifier, outlineIdentifier, .flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
        case modeIdentifier:
            let control = NSSegmentedControl(
                labels: [L("toolbar.source"), L("toolbar.split"), L("toolbar.wysiwyg")],
                trackingMode: .selectOne,
                target: editor,
                action: #selector(EditorViewController.modeControlChanged(_:))
            )
            control.selectedSegment = editor.mode.rawValue
            control.segmentStyle = .texturedRounded
            modeControl = control
            item.view = control
            item.label = L("toolbar.mode")
        case outlineIdentifier:
            let button = NSButton(
                image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: L("menu.outline")) ?? NSImage(),
                target: editor,
                action: #selector(EditorViewController.toggleOutline(_:))
            )
            button.bezelStyle = .texturedRounded
            item.view = button
            item.label = L("menu.outline")
        default:
            return nil
        }
        return item
    }
}
