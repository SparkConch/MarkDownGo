import XCTest
@testable import MarkDownGoCore

final class FrontMatterTests: XCTestCase {
    func testDetectsClosedHeader() {
        let text = "---\ntitle: x\n---\nbody"
        let fm = FrontMatter.detect(in: text)
        XCTAssertFalse(fm.isEmpty)
        XCTAssertEqual(fm.range.length, 17) // "---\ntitle: x\n---\n"
    }

    func testAcceptsDotsCloser() {
        let fm = FrontMatter.detect(in: "---\na: 1\n...\nbody")
        XCTAssertFalse(fm.isEmpty)
    }

    func testIgnoresUnterminatedHeader() {
        XCTAssertTrue(FrontMatter.detect(in: "---\ntitle: x\nbody").isEmpty)
    }

    func testIgnoresHeaderNotAtTop() {
        XCTAssertTrue(FrontMatter.detect(in: "# Hi\n\n---\na: 1\n---").isEmpty)
    }

    func testHandlesCRLF() {
        let fm = FrontMatter.detect(in: "---\r\ntitle: x\r\n---\r\nbody")
        XCTAssertFalse(fm.isEmpty)
    }

    func testPlainDocumentHasNone() {
        XCTAssertTrue(FrontMatter.detect(in: "# Hello").isEmpty)
    }
}
