import SwiftUI
import XCTest
@testable import Sketchy

/// Opt-in renders of the Good Enough wordmark, for before/after crops.
///
/// Skipped unless `GLYPH_FILL_SAMPLES=1` (or `TEST_RUNNER_GLYPH_FILL_SAMPLES=1`)
/// is in the test process environment. Writes PNGs to `GLYPH_FILL_DIR`.
@MainActor
final class GlyphFillPreviewTests: XCTestCase {
    private let phrase = "Good Enough!"
    private let letters = ["o", "e", "a", "h", "b", "p", "q", "d", "g"]

    func testRenderGoodEnoughLabels() throws {
        guard samplesEnabled() else {
            throw XCTSkip("Set GLYPH_FILL_SAMPLES=1 to write glyph fill crops")
        }
        let directory = outputDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let system = UIFont.systemFont(ofSize: 40, weight: .semibold)
        let fredoka = try XCTUnwrap(FredokaFixture.font(size: 40), "Fredoka SemiBold did not load")
        try render(phrase, font: system, name: "system-semibold-good-enough.png", to: directory)
        try render(phrase, font: fredoka, name: "fredoka-semibold-good-enough.png", to: directory)
        for letter in letters {
            try render(letter, font: system, name: "system-semibold-\(letter).png", to: directory)
            try render(letter, font: fredoka, name: "fredoka-semibold-\(letter).png", to: directory)
        }
    }

    private func samplesEnabled() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["GLYPH_FILL_SAMPLES"] == "1"
            || environment["TEST_RUNNER_GLYPH_FILL_SAMPLES"] == "1"
    }

    private func outputDirectory() -> URL {
        let environment = ProcessInfo.processInfo.environment
        let path = environment["GLYPH_FILL_DIR"]
            ?? environment["TEST_RUNNER_GLYPH_FILL_DIR"]
            ?? "/tmp/sketchy-glyph-fill"
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Same bake as SlapDuck's `GoodEnoughLabelCache.render`, on the orange sticker.
    private func render(_ text: String, font: UIFont, name: String, to directory: URL) throws {
        let measured = TextPathConverter.typographicSize(for: text, font: font)
        let canvas = CGSize(width: measured.width + 12, height: measured.height + 12)
        let view = label(text, font: font)
            .padding(6)
            .frame(width: canvas.width, height: canvas.height)
            .background(Color(red: 1, green: 149 / 255, blue: 0))
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: canvas.width, height: canvas.height)
        renderer.scale = 2
        renderer.isOpaque = false
        let image = try XCTUnwrap(renderer.uiImage, "No image for \(name)")
        let data = try XCTUnwrap(image.pngData(), "No PNG for \(name)")
        XCTAssertLessThan(data.count, 10 * 1024 * 1024, "\(name) exceeds 10 MB")
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        NSLog("GLYPH_FILL_CROP %@", url.path)
    }

    private func label(_ text: String, font: UIFont) -> some View {
        let seed = UInt64(bitPattern: Int64(text.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }))
        let outline = Color(red: 71 / 255, green: 71 / 255, blue: 71 / 255)
        return RoughText(text, font: font)
            .fill(Color.white)
            .fillStyle(.solid)
            .stroke(outline)
            .strokeWidth(1.25)
            .strokeCap(.round)
            .strokeJoin(.round)
            .roughness(0)
            .bowing(0)
            .maxRandomnessOffset(0)
            .seed(seed)
    }
}
