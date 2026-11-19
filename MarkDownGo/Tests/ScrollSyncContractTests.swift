import XCTest
@testable import MarkDownGoCore

/// The preview shell and the editor must agree on the scroll vocabulary, or split view drifts.
/// These are source contracts (the test target has no app host), matching PublishContractTests.
final class ScrollSyncContractTests: XCTestCase {
    private var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0...6 {
            url.deleteLastPathComponent()
            if (try? url.appendingPathComponent("project.yml").checkResourceIsReachable()) == true { return url }
        }
        fatalError("repo root not found from \(#filePath)")
    }

    private func read(_ relative: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    func testPreviewExposesSectionScrolling() throws {
        let shell = try read("MarkDownGo/App/PreviewScheme.swift")
        for symbol in ["window.scrollToSection", "window.currentSection"] {
            XCTAssertTrue(shell.contains(symbol), "shell must define \(symbol)")
        }
        // Reporting a bare ratio is what caused the drift; the message must carry a section.
        XCTAssertTrue(shell.contains("postMessage(window.currentSection())"))
    }

    func testEditorMapsSectionsAgainstHeadings() throws {
        let editor = try read("MarkDownGo/App/EditorTextView.swift")
        XCTAssertTrue(editor.contains("func currentSection(headings: [Heading])"))
        XCTAssertTrue(editor.contains("func scrollToSection(_ section: PreviewView.Section, headings: [Heading])"))
        // Recomputing heading offsets lays out the whole document; it must stay cached.
        XCTAssertTrue(editor.contains("func invalidateHeadingTops()"))
    }
    func testModeSwitchAvoidsSynchronousSplitRelayout() throws {
        let controller = try read("MarkDownGo/App/EditorViewController.swift")
        // The preview must not be collapsed or repositioned synchronously inside setMode; the
        // outline sidebar keeps its own animation and is not part of this contract.
        XCTAssertTrue(controller.contains("preview.isHidden = !showPreview"))
        XCTAssertFalse(controller.contains("previewItem?.animator().isCollapsed"),
                       "animated preview collapse stalls on long documents")
        XCTAssertTrue(controller.contains("DispatchQueue.main.async"),
                      "divider movement must happen after the switch paints")
    }
}
