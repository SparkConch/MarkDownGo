import XCTest

/// Contracts about what we ship, checked against the source tree itself (the test target has no app
/// host, and the source tree *is* the contract input). Any violation fails CI before it ships.
final class PublishContractTests: XCTestCase {
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

    // MARK: - Offline preview

    func testVendorManifestIsComplete() throws {
        let required = [
            "MarkDownGo/Resources/preview/vendor/katex/katex.min.css",
            "MarkDownGo/Resources/preview/vendor/katex/katex.min.js",
            "MarkDownGo/Resources/preview/vendor/katex/auto-render.min.js",
            "MarkDownGo/Resources/preview/vendor/mermaid/mermaid.min.js",
        ]
        for path in required {
            let data = try Data(contentsOf: repoRoot.appendingPathComponent(path))
            XCTAssertGreaterThan(data.count, 1_000, "\(path) looks truncated")
        }
    }

    func testKatexFontsAreBundled() throws {
        let fontsDir = repoRoot.appendingPathComponent("MarkDownGo/Resources/preview/vendor/katex/fonts")
        let fonts = try FileManager.default.contentsOfDirectory(atPath: fontsDir.path)
        let woff2 = fonts.filter { $0.hasSuffix(".woff2") }
        XCTAssertGreaterThanOrEqual(woff2.count, 16, "KaTeX renders broken glyphs without its fonts")
    }

    func testPreviewShellHasNoExternalReferences() throws {
        let shell = try read("MarkDownGo/App/PreviewScheme.swift")
        for banned in ["http://", "https://"] {
            XCTAssertFalse(shell.contains(banned), "preview shell must not reference \(banned) — preview is offline by contract")
        }
    }

    func testPreviewShellDefinesTheWholeBridgeContract() throws {
        // One list, both sides: the shell defines these, Swift calls these. A rename that misses
        // one side fails here instead of at runtime.
        let shell = try read("MarkDownGo/App/PreviewScheme.swift")
        for symbol in ["window.render", "window.scrollToRatio", "window.currentScrollRatio", "window.suppressScrollReporting"] {
            XCTAssertTrue(shell.contains("function \(symbol.dropFirst("window.".count))") || shell.contains(symbol),
                          "shell must define \(symbol)")
        }
        let view = try read("MarkDownGo/App/PreviewView.swift")
        for symbol in ["scrollToRatio", "currentScrollRatio", "suppressScrollReporting"] {
            XCTAssertTrue(view.contains(symbol), "Swift bridge must call \(symbol)")
        }
    }

    // MARK: - App icon

    func testAppIconMatrixIsComplete() throws {
        let set = repoRoot.appendingPathComponent("MarkDownGo/Resources/Assets.xcassets/AppIcon.appiconset")
        let contents = try String(contentsOf: set.appendingPathComponent("Contents.json"), encoding: .utf8)
        let expected = ["icon_16x16.png", "icon_16x16@2x.png", "icon_32x32.png", "icon_32x32@2x.png",
                        "icon_128x128.png", "icon_128x128@2x.png", "icon_256x256.png", "icon_256x256@2x.png",
                        "icon_512x512.png", "icon_512x512@2x.png"]
        for name in expected {
            XCTAssertTrue(contents.contains(name), "appiconset missing \(name)")
            let url = set.appendingPathComponent(name)
            XCTAssertNoThrow(try Data(contentsOf: url), "missing file \(name)")
        }
    }

    // MARK: - Build contract

    func testBuildContractFlagsArePresent() throws {
        let project = try read("project.yml")
        XCTAssertTrue(project.contains("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon"))
        XCTAssertTrue(project.contains("-file-compilation-dir"), "build must not embed absolute source paths")
        XCTAssertTrue(project.contains("SWIFT_TREAT_WARNINGS_AS_ERRORS: YES"))
        XCTAssertTrue(project.contains("LSHandlerRank: Owner"), "open-with-us beats the Sega ROM .md")
        XCTAssertTrue(project.contains("NSDocumentClass"), "without it, new-document fails")
    }

    // MARK: - Localization

    func testLocalizationKeysAreInParity() throws {
        func keys(_ path: String) throws -> Set<String> {
            let body = try read(path)
            var found = Set<String>()
            for line in body.split(separator: "\n") where line.hasPrefix("\"") {
                if let end = line.dropFirst().firstIndex(of: "\"") {
                    found.insert(String(line.dropFirst().prefix(upTo: end)))
                }
            }
            return found
        }
        let en = try keys("MarkDownGo/Resources/en.lproj/Localizable.strings")
        let zh = try keys("MarkDownGo/Resources/zh-Hans.lproj/Localizable.strings")
        XCTAssertFalse(en.isEmpty)
        XCTAssertEqual(en.symmetricDifference(zh).sorted(), [], "untranslated keys drift between languages")
    }

    // MARK: - Icon (Apple's official macOS template)

    /// The official template layers, extracted from `macOS 圆角图标模板.psd` via psd-tools:
    /// `512@2x` (824x824 plate) and `512@2x: Shadow` (878x878). The renderer composites
    /// shadow → tinted plate → mark, all clipped to the official silhouette.
    func testOfficialTemplateAssetsExist() throws {
        let plate = try Data(contentsOf: repoRoot.appendingPathComponent("design/official-plate.png"))
        let shadow = try Data(contentsOf: repoRoot.appendingPathComponent("design/official-shadow.png"))
        XCTAssertGreaterThan(plate.count, 1_000, "official plate missing or truncated")
        XCTAssertGreaterThan(shadow.count, 1_000, "official shadow missing or truncated")
        let svg = try read("design/logo.svg")
        XCTAssertTrue(svg.contains("<svg"), "mark source must exist")

        // Small sizes need their own drawing; scaling the 1024 artwork down turns 16px into mush.
        let small = try read("design/logo-small.svg")
        XCTAssertTrue(small.contains("<svg"))
        // The small artwork must equal the standard M/arrow geometry (only shaft/arrow heavier),
        // otherwise a separate drawing can silently drift into a completely different mark.
        let standard = try read("design/logo.svg")
        let mPath = "M232 183 L392 183 L512 343 L632 183 L792 183 L792 632"
        XCTAssertTrue(standard.contains(mPath), "standard M geometry changed")
        XCTAssertTrue(small.contains(mPath), "small artwork must keep the standard M geometry")
        let renderer = try read("scripts/render-icon.swift")
        XCTAssertTrue(renderer.contains("smallSize"), "renderer must special-case small sizes")
        XCTAssertFalse(renderer.contains("designURL(\"logo-small.svg\")"),
                       "renderer must honour its SVG argument, not hard-code the small artwork")
        let script = try read("scripts/make-appicon.sh")
        XCTAssertTrue(script.contains("logo-small.svg"), "make-appicon.sh must pass the small artwork explicitly")
    }

    // MARK: - Themes

    func testEveryThemeShipsLayoutAndTokens() throws {
        let layout = try read("MarkDownGo/Resources/Themes/layout.css")
        XCTAssertTrue(layout.contains("--paper"), "layout must define the token contract")
        for theme in ["xuan", "zhu", "ye"] {
            let css = try read("MarkDownGo/Resources/Themes/\(theme).css")
            for token in ["--paper", "--ink", "--accent", "--serif", "--mono"] {
                XCTAssertTrue(css.contains(token), "\(theme).css missing \(token)")
            }
        }
    }

    func testThemesAreNotAForeignSet() throws {
        // The theme names and tokens came from our own palette; this guards against someone later
        // pasting another product's theme file in wholesale.
        let forbidden = ["OrangeHeart", "Lapis", "Maize", "Phycat", "Rainbow", "wenyan"]
        for theme in ["xuan", "zhu", "ye"] {
            let css = try read("MarkDownGo/Resources/Themes/\(theme).css")
            for name in forbidden {
                XCTAssertFalse(css.contains(name), "\(theme).css must not reference \(name)")
            }
        }
    }

    // MARK: - QuickLook extension

    func testQuickLookExtensionIsDeclared() throws {
        let plist = try read("MarkDownGo/QuickLook/Info.plist")
        XCTAssertTrue(plist.contains("com.apple.quicklook.preview"))
        XCTAssertTrue(plist.contains("QLSupportedContentTypes"))
        XCTAssertTrue(plist.contains("net.daringfireball.markdown"))
        // PlugInKit refuses non-sandboxed QuickLook plugins, so the entitlement is load-bearing.
        let entitlements = try read("MarkDownGo/QuickLook/MarkDownGoQuickLook.entitlements")
        XCTAssertTrue(entitlements.contains("com.apple.security.app-sandbox"))
        let project = try read("project.yml")
        XCTAssertTrue(project.contains("MarkDownGoQuickLook"))
        XCTAssertTrue(project.contains("CODE_SIGN_ENTITLEMENTS"))
    }

    // MARK: - Publish boundary

    func testScaffoldFilesAreNotTracked() throws {
        let gitignore = try read(".gitignore")
        XCTAssertTrue(gitignore.contains("SPEC.md"), "scaffold must stay local")
        XCTAssertTrue(gitignore.contains("design/img-"), "reference artwork must stay local")
    }
}
