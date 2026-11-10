import SwiftUI
import UIKit
import XCTest
@testable import Sketchy

@MainActor
final class SilhouetteShadowTests: XCTestCase {

    func testFootAnchorIsTheLowestOpaqueRow() {
        let image = sprite(canopy: false)
        let foot = SilhouetteShadow.footAnchor(in: image)
        XCTAssertEqual(foot.x, 14, accuracy: 1)
        XCTAssertGreaterThan(foot.y, 50)
        XCTAssertLessThan(foot.y, 64)
    }

    func testTreeShadowSkewsAndStaysPut() throws {
        let image = sprite(canopy: true)
        let shadow = SilhouetteShadow.tree(image: image, at: CGPoint(x: 100, y: 140))
        XCTAssertEqual(shadow.opacity, 0.42, accuracy: 0.001)
        XCTAssertEqual(shadow.transform.c, -0.58, accuracy: 0.001)
        XCTAssertEqual(shadow.transform.d, 0.32, accuracy: 0.001)

        let first = try render(card(shadow))
        let second = try render(card(shadow))
        let ink = darkened(first)
        let again = darkened(second)
        XCTAssertEqual(ink, again)
        XCTAssertFalse(ink.isEmpty)
        let minY = ink.map(\.y).min() ?? 0
        let maxY = ink.map(\.y).max() ?? 0
        let minX = ink.map(\.x).min() ?? 0
        let maxX = ink.map(\.x).max() ?? 0
        XCTAssertLessThan(maxY - minY, 48, "height \(maxY - minY)")
        XCTAssertGreaterThan(maxX - minX, 30, "width \(maxX - minX)")
        let body = ink[ink.count / 2]
        XCTAssertGreaterThan(body.green, body.red, "tint \(body)")

        let clear = SilhouetteShadow.tree(image: image, at: CGPoint(x: 100, y: 140), opacity: 0)
        XCTAssertTrue(darkened(try render(card(clear))).isEmpty)
    }

    func testMaskInitUsesTheAlpha() throws {
        let image = sprite(canopy: false)
        let mask = try XCTUnwrap(image.cgImage)
        let anchor = SilhouetteShadow.footAnchor(in: image)
        let shadow = SilhouetteShadow(
            mask: mask,
            opacity: 0.9,
            transform: .identity,
            anchor: anchor,
            position: CGPoint(x: 80, y: 100),
            scale: 1
        )
        let rendered = try render(card(shadow))
        XCTAssertFalse(darkened(rendered).isEmpty)
    }

    func testRenderSamples() throws {
        guard ProcessInfo.processInfo.environment["SHADOW_SAMPLES"] == "1" else {
            throw XCTSkip("Set SHADOW_SAMPLES=1 to write sample images")
        }
        let dir = ProcessInfo.processInfo.environment["SHADOW_SAMPLE_DIR"] ?? "/tmp/sketchy-shadow-samples"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let image = sprite(canopy: true)
        let shadow = SilhouetteShadow.tree(image: image, at: CGPoint(x: 160, y: 210))
        let view = ZStack(alignment: .topLeading) {
            Color(red: 0.93, green: 0.95, blue: 0.98)
            RoughView()
                .draw(shadow)
            Image(uiImage: image)
                .frame(width: image.size.width, height: image.size.height)
                .position(x: 160 - shadow.anchor.x + image.size.width / 2, y: 210 - shadow.anchor.y + image.size.height / 2)
        }
        .frame(width: 280, height: 280)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.isOpaque = true
        let rendered = try XCTUnwrap(renderer.uiImage)
        let url = URL(fileURLWithPath: dir).appendingPathComponent("tree-shadow.png")
        try XCTUnwrap(rendered.pngData()).write(to: url)
    }

    private func card(_ shadow: SilhouetteShadow) -> some View {
        ZStack {
            Color.white
            RoughView()
                .draw(shadow)
        }
        .frame(width: 200, height: 200)
    }

    private func sprite(canopy: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 28, height: 64), format: format).image { ctx in
            let context = ctx.cgContext
            context.setFillColor(UIColor.red.cgColor)
            context.fill(CGRect(x: 10, y: 16, width: 8, height: 48))
            if canopy {
                context.fillEllipse(in: CGRect(x: 2, y: 0, width: 24, height: 26))
            }
        }
    }

    private func render<V: View>(_ view: V) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = true
        return try XCTUnwrap(renderer.uiImage?.cgImage)
    }

    private struct InkPoint: Equatable {
        var x: Int
        var y: Int
        var red: Int
        var green: Int
        var blue: Int
    }

    private func darkened(_ image: CGImage) -> [InkPoint] {
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
        guard drew else { return [] }
        var hits: [InkPoint] = []
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * image.width * 4 + x * 4
                let sum = Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])
                if sum < 740 {
                    hits.append(InkPoint(
                        x: x,
                        y: image.height - 1 - y,
                        red: Int(pixels[offset]),
                        green: Int(pixels[offset + 1]),
                        blue: Int(pixels[offset + 2])
                    ))
                }
            }
        }
        return hits
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
