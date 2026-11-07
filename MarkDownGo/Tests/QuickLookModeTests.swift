import XCTest
@testable import MarkDownGoCore

/// The preview mode travels from the app to the QuickLook extension as a string inside
/// `config.json`, so its raw values are a contract between two processes, not an implementation
/// detail. Changing one without the other silently falls back to `.rendered`.
final class QuickLookModeTests: XCTestCase {
    func testRawValuesAreStable() {
        XCTAssertEqual(QuickLookMode.rendered.rawValue, "rendered")
        XCTAssertEqual(QuickLookMode.wysiwyg.rawValue, "wysiwyg")
        XCTAssertEqual(QuickLookMode.code.rawValue, "code")
    }

    func testSettingsOffersEveryMode() {
        XCTAssertEqual(QuickLookMode.allCases, [.rendered, .wysiwyg, .code])
    }

    func testUnknownValueFallsBackToRendered() {
        XCTAssertEqual(QuickLookMode(rawValue: "nonsense") ?? .rendered, .rendered)
    }

    func testEveryModeHasAName() {
        for mode in QuickLookMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty, "\(mode.rawValue) has no display name")
        }
    }
}
