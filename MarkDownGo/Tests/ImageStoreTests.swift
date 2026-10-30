import XCTest
@testable import MarkDownGoCore

final class ImageStoreTests: XCTestCase {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private let store = ImageStore()
    private let date = Date(timeIntervalSince1970: 1_793_000_000)

    func testDirectoryModeWritesSiblingFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let doc = dir.appendingPathComponent("notes.md")
        let markdown = try store.markdown(for: png, fileExtension: "png", documentURL: doc, mode: .directory, now: date)
        XCTAssertTrue(markdown.hasPrefix("![image](images/paste-"))
        XCTAssertTrue(markdown.hasSuffix(".png)"))
        let fileName = markdown.dropFirst("![image](images/".count).dropLast(1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: doc.deletingLastPathComponent()
            .appendingPathComponent("images").appendingPathComponent(String(fileName)).path))
    }

    func testDeduplicatesSameSecond() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let doc = dir.appendingPathComponent("notes.md")
        _ = try store.markdown(for: png, fileExtension: "png", documentURL: doc, mode: .directory, now: date)
        let second = try store.markdown(for: png, fileExtension: "png", documentURL: doc, mode: .directory, now: date)
        XCTAssertTrue(second.contains("-2.png"))
    }

    func testBase64ModeInlines() throws {
        let markdown = try store.markdown(for: png, fileExtension: "png", documentURL: nil, mode: .base64, now: date)
        XCTAssertTrue(markdown.hasPrefix("![image](data:image/png;base64,"))
    }

    func testUntitledFallsBackToBase64() throws {
        let markdown = try store.markdown(for: png, fileExtension: "png", documentURL: nil, mode: .directory, now: date)
        XCTAssertTrue(markdown.hasPrefix("![image](data:image/png;base64,"))
    }

    func testMagicByteSniffing() {
        XCTAssertEqual(ImageStore.fileExtension(for: png), "png")
        XCTAssertEqual(ImageStore.fileExtension(for: Data([0xFF, 0xD8, 0xFF, 0xE0])), "jpg")
        XCTAssertEqual(ImageStore.fileExtension(for: Data([0x47, 0x49, 0x46, 0x38])), "gif")
    }
}
