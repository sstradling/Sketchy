import CoreGraphics
import SwiftUI
import XCTest
@testable import Sketchy

/// The cutout shadow follows the finished sheet. It is off unless asked for.
@MainActor
final class StickerShadowTests: XCTestCase {

    func testNoShadowMatchesAZeroOpacityShadow() throws {
        let size = CGSize(width: 220, height: 160)
        let plain = try commands(shadow: nil, size: size)
        let clear = try commands(
            shadow: StickerShadow(opacity: 0, x: 12, y: 16, radius: 8, color: UIColor.black),
            size: size
        )
        XCTAssertEqual(plain.count, clear.count)
        XCTAssertTrue(plain.allSatisfy { $0.sheetShadow == nil })
        XCTAssertTrue(clear.allSatisfy { $0.sheetShadow == nil })
        for (left, right) in zip(plain, clear) {
            XCTAssertEqual(left.path.boundingRect, right.path.boundingRect)
        }
    }

    func testZeroOffsetAndZeroBlurAddsNoShadow() throws {
        let size = CGSize(width: 220, height: 160)
        let commands = try commands(
            shadow: StickerShadow(opacity: 0.8, x: 0, y: 0, radius: 0, color: UIColor.black),
            size: size
        )
        XCTAssertTrue(commands.allSatisfy { $0.sheetShadow == nil })
    }

    func testOffsetAndBlurAreStoredOnTheSheet() throws {
        let size = CGSize(width: 220, height: 160)
        let commands = try commands(
            shadow: StickerShadow(opacity: 0.55, x: -14, y: 9, radius: 6, color: UIColor.black),
            size: size
        )
        let shadows = commands.compactMap(\.sheetShadow)
        XCTAssertEqual(shadows.count, 1)
        XCTAssertEqual(shadows[0].x, -14)
        XCTAssertEqual(shadows[0].y, 9)
        XCTAssertEqual(shadows[0].radius, 6)
        XCTAssertEqual(shadows[0].opacity, 0.55, accuracy: 0.001)
    }

    func testShadowDoesNotChangeTheGeneratedSketch() throws {
        let size = CGSize(width: 200, height: 160)
        var plain = Options()
        plain.roughness = 1.2
        plain.seed = 4
        var shadowed = plain
        shadowed.stickerBacking = StickerBacking(
            width: 12,
            smoothness: 0.4,
            shadow: StickerShadow(opacity: 0.4, x: 8, y: -6, radius: 5, color: UIColor.black)
        )
        let generator = Engine.shared.generator(size: size)
        let shape = Circle(x: 100, y: 80, diameter: 70)
        let left = try XCTUnwrap(generator.generate(drawable: shape, options: plain))
        let right = try XCTUnwrap(generator.generate(drawable: shape, options: shadowed))
        XCTAssertEqual(left.sets.count, right.sets.count)
        for (a, b) in zip(left.sets, right.sets) {
            XCTAssertEqual(a.operations.count, b.operations.count)
        }
    }

    func testGroupCastsOneShadowForTheSharedSheet() {
        let backing = StickerBacking(
            width: 12,
            smoothness: 1,
            shadow: StickerShadow(opacity: 0.6, x: 18, y: 0, radius: 2, color: UIColor.black)
        )
        let size = CGSize(width: 280, height: 180)
        let lines = SketchGroupRenderer.silhouetteLines(
            parts: [
                SketchPart(solidRect(x: 30, y: 40, width: 90, height: 70, color: Color(red: 0.15, green: 0.35, blue: 0.7))),
                SketchPart(solidRect(x: 80, y: 55, width: 80, height: 60, color: Color(red: 0.8, green: 0.3, blue: 0.2)))
            ],
            backing: backing,
            size: size
        )
        let sheet = StickerBackingBuilder.commands(for: lines, outward: backing.width, backing: backing, seed: 3)
        let shadowed = sheet.filter { $0.sheetShadow != nil }
        XCTAssertFalse(shadowed.isEmpty)
        XCTAssertTrue(shadowed.allSatisfy { $0.sheetShadow == shadowed[0].sheetShadow })
        XCTAssertEqual(lines.filter { abs(area($0.points)) > 100 }.count, 1)
    }

    func testPositiveAndNegativeOffsetsFallOnOppositeSides() throws {
        let cream = Color(red: 0.93, green: 0.89, blue: 0.80)
        let right = try render(card(cream, shadowX: 26, shadowY: 0, radius: 0.5))
        let left = try render(card(cream, shadowX: -26, shadowY: 0, radius: 0.5))
        let east = try pixel(right, x: 214, y: 100)
        let westOfRight = try pixel(right, x: 16, y: 100)
        XCTAssertLessThan(east.red, westOfRight.red - 25, "east \(east) west \(westOfRight)")
        let west = try pixel(left, x: 16, y: 100)
        let eastOfLeft = try pixel(left, x: 214, y: 100)
        XCTAssertLessThan(west.red, eastOfLeft.red - 25, "west \(west) east \(eastOfLeft)")
    }

    func testBlurReachesFartherThanAHardShadow() throws {
        let cream = Color(red: 0.93, green: 0.89, blue: 0.80)
        let hard = try render(card(cream, shadowX: 0, shadowY: 0, radius: 2))
        let soft = try render(card(cream, shadowX: 0, shadowY: 0, radius: 14))
        // 18pt past the sheet. A 2pt blur is still cream. A 14pt blur is darker.
        let hardPixel = try pixel(hard, x: 214, y: 100)
        let softPixel = try pixel(soft, x: 214, y: 100)
        XCTAssertLessThan(softPixel.red, hardPixel.red - 8, "soft \(softPixel) hard \(hardPixel)")
    }

    func testHoleStaysClearAndTheGroupSeamHasNoShadowHalo() throws {
        let cream = Color(red: 0.93, green: 0.89, blue: 0.80)
        let holed = try render(holeCard(cream))
        let group = try render(overlapCard(cream))
        // Right side of the hole. The shadow is shifted right, so the left of the
        // hole can show the paper's shadow. The right of the hole stays the card.
        let hole = try pixel(holed, x: 124, y: 93)
        XCTAssertGreaterThan(hole.red, 180, "hole \(hole)")
        let cast = try pixel(holed, x: 208, y: 100)
        XCTAssertLessThan(cast.red, 170, "cast \(cast)")
        // Inside the blue shape, beside the red one. A per-shape shadow would
        // darken this edge. The shared sheet does not.
        let seam = try pixel(group, x: 60, y: 119)
        XCTAssertGreaterThan(seam.blue, seam.red + 20, "seam \(seam)")
        let below = try pixel(group, x: 70, y: 69)
        XCTAssertLessThan(below.red, 80, "below \(below)")
    }

    private func commands(shadow: StickerShadow?, size: CGSize) throws -> [RoughRenderCommand] {
        var options = Options()
        options.roughness = 0
        options.bowing = 0
        options.maxRandomnessOffset = 0
        options.strokeWidth = 4
        options.seed = 2
        options.fill = .clear
        options.stickerBacking = StickerBacking(width: 12, smoothness: 1, shadow: shadow)
        let generator = Engine.shared.generator(size: size)
        let drawing = try XCTUnwrap(
            generator.generate(drawable: Rectangle(x: 40, y: 36, width: 100, height: 60), options: options)
        )
        return SwiftUIRenderer().commands(for: drawing, options: options, in: size)
    }

    private func solidRect(x: Float, y: Float, width: Float, height: Float, color: Color) -> RoughView {
        RoughView()
            .roughness(0)
            .bowing(0)
            .strokeWidth(2)
            .stroke(color)
            .fill(color)
            .fillStyle(.solid)
            .seed(2)
            .draw(Rectangle(x: x, y: y, width: width, height: height))
    }

    private func card(_ background: Color, shadowX: CGFloat, shadowY: CGFloat, radius: CGFloat) -> some View {
        ZStack {
            background
            RoughView()
                .roughness(0)
                .bowing(0)
                .strokeWidth(2)
                .stroke(Color.black)
                .fill(Color.white)
                .fillStyle(.solid)
                .seed(2)
                .stickerBacking(
                    width: 8,
                    smoothness: 1,
                    color: Color.white,
                    shadow: StickerShadow(opacity: 0.9, x: shadowX, y: shadowY, radius: radius, color: UIColor.black)
                )
                .draw(Rectangle(x: 50, y: 50, width: 140, height: 80))
        }
        .frame(width: 280, height: 200)
    }

    private func holeCard(_ background: Color) -> some View {
        ZStack {
            background
            SketchGroup {
                RoughView()
                    .roughness(0)
                    .bowing(0)
                    .strokeWidth(2)
                    .stroke(Color.black)
                    .fill(Color.white)
                    .fillStyle(.hachure)
                    .fillAngle(0)
                    .fillSpacing(5)
                    .seed(2)
                    .draw(Path(d: "M40 36 H180 V150 H40 Z M88 68 H132 V118 H88 Z"))
            }
            .stickerBacking(
                width: 10,
                smoothness: 1,
                color: Color.white,
                shadow: StickerShadow(opacity: 0.9, x: 28, y: 0, radius: 1, color: UIColor.black)
            )
        }
        .frame(width: 280, height: 200)
    }

    private func overlapCard(_ background: Color) -> some View {
        ZStack {
            background
            SketchGroup {
                solidRect(x: 30, y: 36, width: 100, height: 80, color: Color(red: 0.15, green: 0.35, blue: 0.72))
                solidRect(x: 90, y: 50, width: 80, height: 60, color: Color(red: 0.82, green: 0.32, blue: 0.22))
            }
            .stickerBacking(
                width: 10,
                smoothness: 1,
                color: Color.white,
                shadow: StickerShadow(opacity: 0.9, x: 0, y: 8, radius: 0.5, color: UIColor.black)
            )
        }
        .frame(width: 260, height: 200)
    }

    private func area(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            sum += points[index].x * next.y - next.x * points[index].y
        }
        return sum * 0.5
    }

    private func render<V: View>(_ view: V) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = true
        return try XCTUnwrap(renderer.uiImage?.cgImage)
    }

    private struct RGBA {
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
