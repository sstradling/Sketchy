import XCTest
@testable import Sketchy

/// Structure of the README wordmark. These run in a normal suite and need no font.
@MainActor
final class HeaderBannerSpecTests: XCTestCase {
    func testWordmarkSpellsSketchy() {
        let spelled = String(HeaderBannerSpec.letters.map(\.character))
        XCTAssertEqual(spelled, HeaderBannerSpec.text)
    }

    func testExactlyOneStickerAndItIsTheLeadingS() {
        let stickers = HeaderBannerSpec.letters.filter { $0.role == .sticker }
        XCTAssertEqual(stickers.map(\.character), ["S"])
        XCTAssertEqual(HeaderBannerSpec.letters.first?.character, "S")
    }

    func testExactlyOneAnimatedLetterAndItIsTheBang() {
        let animated = HeaderBannerSpec.letters.filter { $0.role == .animated }
        XCTAssertEqual(animated.map(\.character), ["!"])
    }

    func testEveryLetterHasADistinctSeed() {
        let seeds = HeaderBannerSpec.letters.map(\.seed)
        XCTAssertEqual(Set(seeds).count, seeds.count)
    }

    func testAnimationIsSeededAndLoopsOverEveryFrame() {
        XCTAssertNotNil(HeaderBannerAnimation.config.seed)
        XCTAssertEqual(HeaderBannerAnimation.config.steps, HeaderBannerAnimation.frameCount)
        XCTAssertGreaterThanOrEqual(HeaderBannerAnimation.frameCount, 2)
    }

    func testStickerIsWhitePaperWithASmoothEdgeAndAShadow() throws {
        let backing = HeaderSticker.backing
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(backing.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual([red, green, blue, alpha], [1, 1, 1, 1])
        XCTAssertEqual(backing.edge, .smooth)
        XCTAssertGreaterThan(backing.width, 0)
        XCTAssertGreaterThan(HeaderSticker.shadowOpacity, 0)
        XCTAssertLessThanOrEqual(HeaderSticker.shadowOpacity, 0.5)
    }

    func testStickerSheetAndShadowFitInsideTheLetterPadding() {
        let letter = HeaderBannerSpec.letters[0]
        let reach = HeaderSticker.reach(strokeWidth: CGFloat(letter.strokeWidth))
        XCTAssertLessThanOrEqual(reach, HeaderBannerLayout.letterPadding + 4)
    }

    func testPlacementsRunLeftToRightInsideTheCard() throws {
        let font = try XCTUnwrap(UIFont(name: "Helvetica-Bold", size: HeaderBannerLayout.fontSize))
        let placements = HeaderBannerLayoutSolver.placements(font: font)
        XCTAssertEqual(placements.count, HeaderBannerSpec.letters.count)
        for pair in zip(placements, placements.dropFirst()) {
            XCTAssertLessThan(pair.0.origin.x, pair.1.origin.x)
        }
        let first = try XCTUnwrap(placements.first)
        let last = try XCTUnwrap(placements.last)
        XCTAssertGreaterThan(first.origin.x, HeaderBannerLayout.marginX)
        XCTAssertLessThan(last.origin.x + last.size.width, HeaderBannerLayout.width)
    }
}

/// Renders the wordmark frames only when `TEST_RUNNER_RENDER_HEADER=1`.
///
/// `scripts/render-header.sh` sets that variable on the booted simulator, then
/// assembles the PNG frames into `docs/images/header.gif`. A normal suite skips this test.
@MainActor
final class HeaderBannerRenderTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        let environment = ProcessInfo.processInfo.environment
        let enabled = environment["TEST_RUNNER_RENDER_HEADER"] == "1" || environment["RENDER_HEADER"] == "1"
        try XCTSkipUnless(enabled, "Header rendering is opt-in. Set TEST_RUNNER_RENDER_HEADER=1.")
    }

    func testRenderHeaderFrames() throws {
        let directory = try HeaderBannerRenderer.resolveOutputDirectory()
        try HeaderBannerRenderer.render(to: directory)
        let manifest = directory.appending(path: "manifest.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path))
    }
}
