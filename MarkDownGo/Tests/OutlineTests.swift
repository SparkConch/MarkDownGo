import XCTest
@testable import MarkDownGoCore

final class OutlineTests: XCTestCase {
    func testExtractsNestedHeadings() {
        let headings = Outline.headings(in: "# A\n## Sub\n### Deep\n## Sub2\nbody")
        XCTAssertEqual(headings.map(\.level), [1, 2, 3, 2])
        XCTAssertEqual(headings.map(\.title), ["A", "Sub", "Deep", "Sub2"])
        XCTAssertEqual(headings[1].lineStart, 4)
    }

    func testSkipsHeadingsInsideFences() {
        let headings = Outline.headings(in: "```\n# not a heading\n```\n\n# Real")
        XCTAssertEqual(headings.map(\.title), ["Real"])
    }

    func testSkipsFrontMatter() {
        let headings = Outline.headings(in: "---\ntitle: Fake\n---\n\n# Real")
        XCTAssertEqual(headings.map(\.title), ["Real"])
    }

    func testCJK() {
        let headings = Outline.headings(in: "# 概述\n## 背景")
        XCTAssertEqual(headings.map(\.title), ["概述", "背景"])
    }
}
