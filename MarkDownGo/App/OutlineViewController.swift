import AppKit
import MarkDownGoCore

/// Left sidebar: heading tree built by a stack pass over the level sequence.
final class OutlineViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var onSelect: ((Int) -> Void)?

    private let outlineView = NSOutlineView()
    private var roots: [Node] = []

    final class Node {
        let heading: Heading
        var children: [Node] = []
        init(_ heading: Heading) { self.heading = heading }
    }

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.indentationPerLevel = 10
        outlineView.rowHeight = 26
        outlineView.focusRingType = .none
        scroll.documentView = outlineView
        view = scroll
    }

    func reload(_ headings: [Heading]) {
        var roots: [Node] = []
        var stack: [(level: Int, node: Node)] = []
        for heading in headings {
            let node = Node(heading)
            while let top = stack.last, top.level >= heading.level { stack.removeLast() }
            if let parent = stack.last?.node { parent.children.append(node) } else { roots.append(node) }
            stack.append((heading.level, node))
        }
        self.roots = roots
        outlineView.reloadData()
        for root in roots { outlineView.expandItem(root, expandChildren: true) }
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Node)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Node)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? Node)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        let label = NSTextField(labelWithString: node.heading.title)
        label.font = .systemFont(ofSize: node.heading.level <= 2 ? 13 : 12)
        label.textColor = node.heading.level <= 2 ? .labelColor : .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat { 24 }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? Node else { return }
        onSelect?(node.heading.lineStart)
    }
}
