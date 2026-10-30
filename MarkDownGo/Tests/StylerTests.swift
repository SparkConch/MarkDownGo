import XCTest
@testable import MarkDownGoCore

final class StylerTests: XCTestCase {
    private func line(_ styled: StyledText, _ index: Int) -> [StyleKind] {
        styled.tokens[index].map(\.kind)
    }

    private func first(_ styled: StyledText, _ index: Int, _ kind: StyleKind) -> StyleToken? {
        styled.tokens[index].first { $0.kind == kind }
    }

    func testATXHeadingRanges() {
        let styled = Styler.style("# Title")
        XCTAssertEqual(styled.lines.count, 1)
        XCTAssertEqual(first(styled, 0, .headingMark(1))?.range, NSRange(location: 0, length: 2))
        XCTAssertEqual(first(styled, 0, .headingText(1))?.range, NSRange(location: 2, length: 5))
    }

    func testCJKHeading() {
        let styled = Styler.style("## 中文标题")
        XCTAssertEqual(first(styled, 0, .headingMark(2))?.range, NSRange(location: 0, length: 3))
        XCTAssertEqual(first(styled, 0, .headingText(2))?.range, NSRange(location: 3, length: 4))
    }

    func testFencedCode() {
        let styled = Styler.style("```swift\nlet a = 1\n```\nafter")
        XCTAssertEqual(line(styled, 0), [.fenceMark])
        XCTAssertEqual(line(styled, 1), [.codeBlock])
        XCTAssertEqual(line(styled, 2), [.fenceMark])
    }

    func testQuoteAndList() {
        let styled = Styler.style("> quoted text\n- item\n1. second")
        XCTAssertEqual(first(styled, 0, .quoteMark)?.range, NSRange(location: 0, length: 2))
        XCTAssertEqual(first(styled, 0, .quoteText)?.range, NSRange(location: 2, length: 11))
        XCTAssertNotNil(first(styled, 1, .listMark))
        XCTAssertNotNil(first(styled, 2, .listMark))
    }

    func testTaskListMarker() {
        let styled = Styler.style("- [x] done")
        XCTAssertNotNil(first(styled, 0, .listMark))
        XCTAssertEqual(first(styled, 0, .taskMark)?.range, NSRange(location: 2, length: 4))
    }

    func testStrongAndLink() {
        let styled = Styler.style("see **bold** and [docs](https://example.com) ok")
        XCTAssertNotNil(first(styled, 0, .strong))
        XCTAssertNotNil(first(styled, 0, .strongMark))
        XCTAssertEqual(first(styled, 0, .linkText)?.range, NSRange(location: 18, length: 4))
        XCTAssertEqual(first(styled, 0, .linkURL)?.range, NSRange(location: 24, length: 19))
    }

    func testSetextHeading() {
        let styled = Styler.style("Title\n=====\nbody")
        XCTAssertEqual(first(styled, 0, .headingText(1))?.range, NSRange(location: 0, length: 5))
        XCTAssertEqual(first(styled, 1, .headingMark(1))?.range, NSRange(location: 6, length: 5))
    }

    func testThematicBreakVsFrontMatter() {
        XCTAssertTrue(line(Styler.style("***"), 0).contains(.horizontalRule))
    }

    func testFrontMatterTokenizedVerbatim() {
        let styled = Styler.style("---\ntitle: x\n---\ntext")
        XCTAssertEqual(line(styled, 0), [.frontMatter])
        XCTAssertEqual(line(styled, 1), [.frontMatter])
        XCTAssertEqual(line(styled, 2), [.frontMatter])
        XCTAssertEqual(line(styled, 3), [])
    }

    func testMarkersHiddenInWYSIWYGIsViewSide() {
        XCTAssertTrue(StyleKind.headingMark(1).isMarker)
        XCTAssertFalse(StyleKind.headingText(1).isMarker)
    }

    func testLineIndexBinarySearch() {
        let styled = Styler.style("one\ntwo\nthree")
        XCTAssertEqual(styled.lineIndex(forCharacter: 0), 0)
        XCTAssertEqual(styled.lineIndex(forCharacter: 3), 0)
        XCTAssertEqual(styled.lineIndex(forCharacter: 4), 1)
        XCTAssertEqual(styled.lineIndex(forCharacter: 99), 2)
    }

    func testInlineCodeInQuote() {
        let styled = Styler.style("> use `code` here")
        XCTAssertNotNil(first(styled, 0, .codeSpan))
        XCTAssertNotNil(first(styled, 0, .quoteMark))
    }
}
