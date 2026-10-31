import XCTest
@testable import MarkDownGoCore

final class TextEncodingTests: XCTestCase {
    private let sample = "# 标题\n\n中文内容 with English mixed.\n"

    func testUTF8RoundTripAndDetection() {
        let data = sample.data(using: .utf8)!
        XCTAssertEqual(TextEncoding.detect(data), .utf8)
        XCTAssertEqual(String(data: data, encoding: TextEncoding.utf8.cfEncoding), sample)
    }

    func testGB18030DetectedAndRoundTrips() {
        let enc = TextEncoding.gb18030
        let data = sample.data(using: enc.cfEncoding)!
        XCTAssertEqual(TextEncoding.detect(data), .gb18030)
        XCTAssertEqual(String(data: data, encoding: enc.cfEncoding), sample)
    }

    func testBig5AmbiguityIsDocumentedNotLossy() {
        // GB18030, Big5 and Shift-JIS are byte-legality indistinguishable (see TextEncoding's
        // header). A Big5 file may be *labelled* gb18030; the contract we actually keep is
        // "decode losslessly, re-encode to identical bytes" — no data moves.
        let traditional = "這是繁體中文測試。\n"
        let data = traditional.data(using: TextEncoding.big5.cfEncoding)!
        let detected = TextEncoding.detect(data)
        XCTAssertTrue([.gb18030, .big5].contains(detected), "got \(detected)")
        let text = String(data: data, encoding: detected.cfEncoding)!
        XCTAssertEqual(text.data(using: detected.cfEncoding), data, "labelled encoding must round-trip the file")
    }

    func testShiftJAmbiguityIsDocumentedNotLossy() {
        let japanese = "これは日本語のテストです。\n"
        let data = japanese.data(using: TextEncoding.shiftJIS.cfEncoding)!
        let detected = TextEncoding.detect(data)
        XCTAssertTrue([.gb18030, .shiftJIS].contains(detected), "got \(detected)")
        let text = String(data: data, encoding: detected.cfEncoding)!
        XCTAssertEqual(text.data(using: detected.cfEncoding), data, "labelled encoding must round-trip the file")
    }

    func testUTF16BOMDetected() {
        // UTF-16 is only ever detected through its BOM: without one, any byte pair "decodes",
        // so guessing would corrupt far more files than it fixes.
        var le = Data([0xFF, 0xFE])
        le.append(sample.data(using: .utf16LittleEndian)!)
        var be = Data([0xFE, 0xFF])
        be.append(sample.data(using: .utf16BigEndian)!)
        XCTAssertEqual(TextEncoding.detect(le), .utf16LE)
        XCTAssertEqual(TextEncoding.detect(be), .utf16BE)
    }

    func testUTF16WithoutBOMIsNotGuessed() {
        let bare = sample.data(using: .utf16LittleEndian)!
        XCTAssertNotEqual(TextEncoding.detect(bare), .utf16LE)
    }

    func testLatin1FallbackNeverFails() {
        // 0x80 is invalid as a lead byte in every multi-byte candidate and outside ASCII, so the
        // single-byte fallback takes it (€ in windows-1252).
        let data = Data([0x41, 0x80, 0x0A])
        XCTAssertEqual(TextEncoding.detect(data), .windows1252)
        XCTAssertEqual(String(data: data, encoding: TextEncoding.windows1252.cfEncoding), "A\u{20AC}\n")
    }

    func testEncodeReturnsNilForUnrepresentable() {
        XCTAssertNil(TextEncoding.big5.encode("🦆 emoji"))
        XCTAssertNotNil(TextEncoding.big5.encode("這是繁體中文。"))
        XCTAssertNotNil(TextEncoding.utf8.encode("🦆"))
    }

    func testMislabelledLegacyFileSurvivesSave() {
        // The scenario behind the ambiguity note: a Big5 file labelled gb18030 must produce
        // byte-identical output when saved through Document's encoding-keep path.
        let traditional = "這是繁體中文測試。\n"
        let original = traditional.data(using: TextEncoding.big5.cfEncoding)!
        let detected = TextEncoding.detect(original)
        let text = String(data: original, encoding: detected.cfEncoding)!
        XCTAssertEqual(detected.encode(text), original)
    }

    func testEmptyDataIsUTF8() {
        XCTAssertEqual(TextEncoding.detect(Data()), .utf8)
    }

    func testDetectionOrderHasUTF8First() {
        XCTAssertEqual(TextEncoding.detectionOrder.first, .utf8)
    }
}
