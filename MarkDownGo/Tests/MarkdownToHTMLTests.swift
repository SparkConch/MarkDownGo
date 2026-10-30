import XCTest
@testable import MarkDownGoCore

final class MarkdownToHTMLTests: XCTestCase {
    func testTable() {
        let html = MarkdownToHTML.render("| a | b |\n|---|---|\n| 1 | 2 |")
        XCTAssertTrue(html.contains("<table"))
        XCTAssertTrue(html.contains("<td"))
    }

    func testStrikethrough() {
        XCTAssertTrue(MarkdownToHTML.render("~~gone~~").contains("<del>"))
    }

    func testTaskList() {
        let html = MarkdownToHTML.render("- [x] done\n- [ ] todo")
        XCTAssertTrue(html.contains("checkbox"))
    }

    func testFootnote() {
        let html = MarkdownToHTML.render("Text[^1]\n\n[^1]: Note body")
        XCTAssertTrue(html.contains("footnote"), html)
    }

    func testFrontMatterDropped() {
        let html = MarkdownToHTML.render("---\ntitle: secret\n---\n\n# Hi")
        XCTAssertTrue(html.contains("<h1>Hi</h1>"))
        XCTAssertFalse(html.contains("secret"))
    }

    func testMermaidFencePreserved() {
        let html = MarkdownToHTML.render("```mermaid\ngraph TD\nA-->B\n```")
        XCTAssertTrue(html.contains("language-mermaid"))
    }
}
