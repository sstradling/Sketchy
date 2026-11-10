import SwiftUI
import UIKit
import XCTest
@testable import Sketchy

@MainActor
final class InteriorShadeTests: XCTestCase {

    func testShadeDoesNotChangeTheCachedSketch() {
        var plain = quiet()
        var shaded = plain
        shaded.interiorShades = [.pitShadow, .pitRecess, .halo(color: Color.red)]
        let drawable = Circle(x: 80, y: 80, diameter: 100)
        let left = generate(drawable, options: plain)
        let right = generate(drawable, options: shaded)
        XCTAssertEqual(left?.sets.count, right?.sets.count)
        XCTAssertEqual(left?.sets.first?.operations.count, right?.sets.first?.operations.count)
        XCTAssertNotEqual(plain.cacheHash, shaded.cacheHash)

        let size = CGSize(width: 160, height: 160)
        let keyA = DrawingCacheKey(drawable: drawable, size: size, options: plain)
        let keyB = DrawingCacheKey(drawable: drawable, size: size, options: shaded)
        XCTAssertEqual(keyA, keyB)

        let commands = SwiftUIRenderer().commands(for: right!, options: shaded, in: size)
        XCTAssertEqual(commands.filter { $0.shade != nil }.count, 3)
        let kinds = commands.compactMap(\.shade)
        XCTAssertFalse(kinds[0].paintsOutside)
        XCTAssertFalse(kinds[1].paintsOutside)
        XCTAssertTrue(kinds[2].paintsOutside)
    }

    func testInnerShadowDarkensTheTopAndStaysInside() throws {
        let image = try render(card(shades: [.innerShadow(opacity: 0.95, x: 0, y: 14, blur: 6)]))
        // The sampler's y matches StickerShadowTests: larger y is the visual top.
        let top = try pixel(image, x: 80, y: 118)
        let bottom = try pixel(image, x: 80, y: 42)
        let outside = try pixel(image, x: 80, y: 18)
        XCTAssertLessThan(top.red, bottom.red - 12, "top \(top) bottom \(bottom)")
        XCTAssertGreaterThan(outside.red, 240, "outside \(outside)")
    }

    func testRecessIsDarkerAtTheTop() throws {
        let image = try render(card(shades: [.pitRecess]))
        let top = try pixel(image, x: 80, y: 120)
        let bottom = try pixel(image, x: 80, y: 40)
        XCTAssertLessThan(top.red, 140, "top \(top)")
        XCTAssertGreaterThan(bottom.red, top.red + 30, "bottom \(bottom)")
    }

    func testEdgeShadeLeavesTheCenterClear() throws {
        let image = try render(card(shades: [.edgeShade(color: Color.black, opacity: 0.8, inner: 0.45)]))
        let center = try pixel(image, x: 80, y: 80)
        let rim = try pixel(image, x: 80, y: 38)
        XCTAssertGreaterThan(center.red, 230, "center \(center)")
        XCTAssertLessThan(rim.red, center.red - 30, "rim \(rim)")
    }

    func testHaloSitsOutsideTheDisc() throws {
        let image = try render(card(shades: [.halo(color: Color.red, opacity: 0.9, glow: 0.2, width: 8, blur: 1)]))
        let outside = try pixel(image, x: 80, y: 22)
        let center = try pixel(image, x: 80, y: 80)
        XCTAssertGreaterThan(outside.red, outside.blue + 20, "halo \(outside)")
        XCTAssertGreaterThan(center.red, 230, "center \(center)")
        XCTAssertGreaterThan(center.green, 230)
    }

    func testHoleStaysEmpty() throws {
        let d = "M0 0 H160 V160 H0 Z M50 50 H110 V110 H50 Z"
        let view = ZStack {
            Color.blue
            RoughView()
                .roughness(0)
                .bowing(0)
                .maxRandomnessOffset(0)
                .stroke(Color.clear)
                .strokeWidth(0)
                .fill(Color.white)
                .fillStyle(.solid)
                .seed(3)
                .interiorShades([.pitRecess])
                .draw(Path(d: d))
        }
        .frame(width: 160, height: 160)
        let image = try render(view)
        let hole = try pixel(image, x: 80, y: 80)
        let material = try pixel(image, x: 80, y: 20)
        XCTAssertGreaterThan(hole.blue, hole.red + 40, "hole \(hole)")
        XCTAssertGreaterThan(material.red, 140, "material \(material)")
        XCTAssertLessThan(abs(material.red - material.blue), 20, "material \(material)")
    }

    func testRepeatedRenderMatches() throws {
        let view = card(shades: [.pitShadow, .pitRecess])
        let first = try render(view)
        let second = try render(view)
        let a = try pixel(first, x: 80, y: 42)
        let b = try pixel(second, x: 80, y: 42)
        XCTAssertEqual(a, b)
    }

    func testRenderSamples() throws {
        guard ProcessInfo.processInfo.environment["INTERIOR_SAMPLES"] == "1" else {
            throw XCTSkip("Set INTERIOR_SAMPLES=1 to write sample images")
        }
        let dir = ProcessInfo.processInfo.environment["INTERIOR_SAMPLE_DIR"] ?? "/tmp/sketchy-interior-samples"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try write(pitSample(), name: "pit-shadow.png", dir: dir)
        try write(glowSample(), name: "hit-glow.png", dir: dir)
        try write(edgeSample(), name: "edge-shade.png", dir: dir)
    }

    private func pitSample() -> some View {
        ZStack {
            Color(red: 0.93, green: 0.95, blue: 0.98)
            RoughView()
                .roughness(0.4)
                .bowing(0.4)
                .stroke(Color.white)
                .strokeWidth(6)
                .fill(Color(red: 0.55, green: 0.08, blue: 0.1))
                .fillStyle(.solid)
                .seed(11)
                .interiorShades([.pitShadow, .pitRecess])
                .draw(Circle(x: 120, y: 120, diameter: 150))
        }
        .frame(width: 240, height: 240)
    }

    private func glowSample() -> some View {
        ZStack {
            Color(red: 0.93, green: 0.95, blue: 0.98)
            RoughView()
                .roughness(1.1)
                .bowing(1)
                .stroke(Color(red: 0.15, green: 0.1, blue: 0.08))
                .strokeWidth(3)
                .fill(Color.white)
                .fillStyle(.solid)
                .seed(19)
                .interiorShade(.halo(
                    color: Color(red: 1, green: 0.23, blue: 0.19),
                    opacity: 0.55,
                    glow: 0.35,
                    width: 3.5,
                    blur: 2
                ))
                .draw(Circle(x: 120, y: 120, diameter: 90))
        }
        .frame(width: 240, height: 240)
    }

    private func edgeSample() -> some View {
        ZStack {
            Color(red: 0.93, green: 0.95, blue: 0.98)
            RoughView()
                .roughness(0.6)
                .stroke(Color(red: 0.15, green: 0.1, blue: 0.08))
                .strokeWidth(2.5)
                .fill(Color.white)
                .fillStyle(.solid)
                .seed(23)
                .interiorShade(.edgeShade())
                .draw(Circle(x: 120, y: 120, diameter: 140))
        }
        .frame(width: 240, height: 240)
    }

    private func write<V: View>(_ view: V, name: String, dir: String) throws {
        let image = try render(view, scale: 2)
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
        guard let data = UIImage(cgImage: image).pngData() else {
            XCTFail("png")
            return
        }
        try data.write(to: url)
    }

    private func card(shades: [InteriorShade]) -> some View {
        ZStack {
            Color.white
            RoughView()
                .roughness(0)
                .bowing(0)
                .maxRandomnessOffset(0)
                .stroke(Color.white)
                .strokeWidth(1)
                .fill(Color.white)
                .fillStyle(.solid)
                .seed(2)
                .interiorShades(shades)
                .draw(Circle(x: 80, y: 80, diameter: 100))
        }
        .frame(width: 160, height: 160)
    }

    private func generate(_ drawable: Drawable, options: Options) -> Drawing? {
        NativeGenerator(size: CGSize(width: 160, height: 160)).generate(
            drawable: drawable,
            options: options
        )
    }

    private func quiet() -> Options {
        var options = Options()
        options.roughness = 0
        options.bowing = 0
        options.maxRandomnessOffset = 0
        options.strokeWidth = 2
        options.fillStyle = .solid
        options.seed = 4
        return options
    }

    private func render<V: View>(_ view: V, scale: CGFloat = 1) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: nil, height: nil)
        renderer.isOpaque = true
        return try XCTUnwrap(renderer.uiImage?.cgImage)
    }

    private struct RGBA: Equatable {
        var red: Int
        var green: Int
        var blue: Int
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> RGBA {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        XCTAssertTrue(drew)
        let flipped = image.height - 1 - y
        let offset = flipped * image.width * 4 + x * 4
        return RGBA(red: Int(pixels[offset]), green: Int(pixels[offset + 1]), blue: Int(pixels[offset + 2]))
    }
}
