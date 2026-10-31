import XCTest
@testable import MarkDownGoCore

final class FileChangePolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)

    func testNewerDiskReloadsWhenClean() {
        XCTAssertEqual(FileChangePolicy.resolve(currentModificationDate: t0, diskModificationDate: t1, hasUnsavedEdits: false), .reload)
    }

    func testNewerDiskKeepsUnsavedEdits() {
        XCTAssertEqual(FileChangePolicy.resolve(currentModificationDate: t0, diskModificationDate: t1, hasUnsavedEdits: true), .keepLocalEdits)
    }

    func testSameOrOlderDiskIgnored() {
        XCTAssertEqual(FileChangePolicy.resolve(currentModificationDate: t1, diskModificationDate: t1, hasUnsavedEdits: false), .ignore)
        XCTAssertEqual(FileChangePolicy.resolve(currentModificationDate: t1, diskModificationDate: t0, hasUnsavedEdits: false), .ignore)
    }

    func testMissingDiskDateIgnored() {
        XCTAssertEqual(FileChangePolicy.resolve(currentModificationDate: t0, diskModificationDate: nil, hasUnsavedEdits: false), .ignore)
    }

    func testFirstReadWithoutCurrentDateReloads() {
        // fileModificationDate is nil before the first save; a presenter notification then means
        // somebody wrote the file after we read it — reload.
        XCTAssertEqual(FileChangePolicy.resolve(currentModificationDate: nil, diskModificationDate: t1, hasUnsavedEdits: false), .reload)
    }
}
