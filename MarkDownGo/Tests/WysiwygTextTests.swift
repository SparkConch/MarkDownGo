import XCTest
@testable import MarkDownGoCore

final class WysiwygTextTests: XCTestCase {
    private func make(_ text: String) -> WysiwygText {
        WysiwygText.make(from: text, styled: Styler.style(text))
    }

    func testHeadingMarkRemoved() {
        XCTAssertEqual(make("# Title").string, "Title")
        XCTAssertEqual(make("## 中文标题").string, "中文标题")
    }

    func testEmphasisMarksRemoved() {
        XCTAssertEqual(make("a **bold** b").string, "a bold b")
        XCTAssertEqual(make("x *it* y").string, "x it y")
        XCTAssertEqual(make("~~gone~~").string, "gone")
    }

    func testLinkKeepsTextDropsURL() {
        XCTAssertEqual(make("see [docs](https://example.com/a) now").string, "see docs now")
    }

    func testImageKeepsAltOnly() {
        XCTAssertEqual(make("![图](images/a.png)").string, "图")
    }

    func testQuoteAndFenceMarksRemoved() {
        XCTAssertEqual(make("> quoted").string, "quoted")
        XCTAssertEqual(make("```swift\nlet a = 1\n```").string, "\nlet a = 1\n")
    }

    func testBulletsBecomeDotsAndOrderedNumbersStay() {
        XCTAssertEqual(make("- one\n- two").string, "• one\n• two")
        XCTAssertEqual(make("1. first").string, "first")
    }

    func testTaskBoxes() {
        XCTAssertEqual(make("- [ ] todo").string, "☐ todo")
        XCTAssertEqual(make("- [x] done").string, "☑ done")
    }

    func testFrontMatterDropped() {
        let text = "---\ntitle: Hi\n---\n# Body"
        XCTAssertEqual(make(text).string, "Body")
    }

    /// The point of the remap: a token must cover the same characters after the marks are gone.
    func testTokenRangesFollowTheText() {
        let content = make("## Hello **world**")
        XCTAssertEqual(content.string, "Hello world")
        let bold = content.tokens.first { $0.kind == .strong }
        XCTAssertEqual(bold?.range, NSRange(location: 6, length: 5))
        XCTAssertEqual((content.string as NSString).substring(with: bold!.range), "world")
        for token in content.tokens {
            XCTAssertLessThanOrEqual(NSMaxRange(token.range), (content.string as NSString).length)
        }
    }

    func testPlainParagraphHasNoTokens() {
        let content = make("just words")
        XCTAssertEqual(content.string, "just words")
        XCTAssertTrue(content.tokens.isEmpty)
    }
}
