import CoreGraphics
import SwiftUI
import XCTest
@testable import Sketchy

/// One shared sheet for several drawings. Geometry is checked on the union
/// and on pixels, so an internal edge cannot grow its own halo.
@MainActor
final class GroupBackingTests: XCTestCase {

    func testOverlappingSquaresBecomeOneExterior() {
        let rings = [
            square(CGRect(x: 0, y: 0, width: 100, height: 80), shape: 0),
            square(CGRect(x: 60, y: 0, width: 100, height: 80), shape: 1)
        ]
        let combined = SilhouetteUnion.combine(rings)
        let exteriors = combined.filter { !$0.isHole }
        XCTAssertEqual(exteriors.count, 1)
        XCTAssertTrue(combined.allSatisfy { !$0.isHole })
        XCTAssertTrue(covered(CGPoint(x: 30, y: 40), combined))
        XCTAssertTrue(covered(CGPoint(x: 80, y: 40), combined))
        XCTAssertTrue(covered(CGPoint(x: 140, y: 40), combined))
        XCTAssertFalse(covered(CGPoint(x: 180, y: 40), combined))
        XCTAssertFalse(covered(CGPoint(x: 80, y: -10), combined))
    }

    func testDisconnectedSquaresStaySeparate() {
        let rings = [
            square(CGRect(x: 0, y: 0, width: 40, height: 40), shape: 0),
            square(CGRect(x: 200, y: 10, width: 40, height: 40), shape: 1)
        ]
        let combined = SilhouetteUnion.combine(rings)
        XCTAssertEqual(combined.filter { !$0.isHole }.count, 2)
        XCTAssertFalse(covered(CGPoint(x: 120, y: 20), combined))
        for ring in combined {
            XCTAssertLessThan(bounds(ring.points).width, 70)
        }
    }

    func testAHoleStaysOpenUntilAnotherShapeFillsIt() {
        let outer = square(CGRect(x: 0, y: 0, width: 120, height: 120), shape: 0)
        let hole = square(CGRect(x: 40, y: 40, width: 40, height: 40), shape: 0)
        let open = SilhouetteUnion.combine([outer, hole])
        XCTAssertEqual(open.filter(\.isHole).count, 1)
        XCTAssertFalse(sheetCovers(CGPoint(x: 60, y: 60), open))
        XCTAssertTrue(sheetCovers(CGPoint(x: 20, y: 60), open))

        let plug = square(CGRect(x: 36, y: 36, width: 48, height: 48), shape: 1)
        let filled = SilhouetteUnion.combine([outer, hole, plug])
        XCTAssertTrue(filled.allSatisfy { !$0.isHole })
        XCTAssertTrue(sheetCovers(CGPoint(x: 60, y: 60), filled))
        XCTAssertFalse(sheetCovers(CGPoint(x: 130, y: 60), filled))
    }

    func testCornerContactDoesNotBridgeTheGap() {
        let rings = [
            square(CGRect(x: 0, y: 0, width: 50, height: 50), shape: 0),
            square(CGRect(x: 50, y: 50, width: 50, height: 50), shape: 1)
        ]
        let combined = SilhouetteUnion.combine(rings)
        XCTAssertEqual(combined.filter { !$0.isHole }.count, 2)
        XCTAssertFalse(covered(CGPoint(x: 25, y: 75), combined))
        XCTAssertFalse(covered(CGPoint(x: 75, y: 25), combined))
        XCTAssertTrue(covered(CGPoint(x: 10, y: 10), combined))
        XCTAssertTrue(covered(CGPoint(x: 80, y: 80), combined))
    }

    func testScaleAndRotationMoveTheSilhouette() {
        let backing = StickerBacking(width: 8, smoothness: 1)
        let size = CGSize(width: 360, height: 360)
        let base = SketchPart(cleanRect(x: 40, y: 30, width: 50, height: 24))
        let plain = bounds(SketchGroupRenderer.silhouetteLines(
            parts: [base],
            backing: backing,
            size: size
        ).flatMap(\.points))
        let scaled = bounds(SketchGroupRenderer.silhouetteLines(
            parts: [base.sketchScale(2)],
            backing: backing,
            size: size
        ).flatMap(\.points))
        XCTAssertEqual(scaled.midX, plain.midX * 2, accuracy: 10)
        XCTAssertGreaterThan(scaled.width, plain.width + 20)

        let pivot = CGPoint(x: plain.midX, y: plain.midY)
        let turned = bounds(SketchGroupRenderer.silhouetteLines(
            parts: [base.sketchRotation(.degrees(90), around: pivot)],
            backing: backing,
            size: size
        ).flatMap(\.points))
        XCTAssertEqual(turned.width, plain.height, accuracy: 8)
        XCTAssertEqual(turned.height, plain.width, accuracy: 8)
    }

    func testGroupSheetFollowsAPartOffset() {
        let backing = StickerBacking(width: 10, smoothness: 1)
        let size = CGSize(width: 240, height: 180)
        let moved = SketchGroupRenderer.silhouetteLines(
            parts: [
                SketchPart(cleanRect(x: 20, y: 20, width: 60, height: 40)).sketchOffset(x: 30, y: 15)
            ],
            backing: backing,
            size: size
        )
        let box = bounds(moved.flatMap(\.points))
        XCTAssertEqual(box.midX, 80, accuracy: 8)
        XCTAssertEqual(box.midY, 55, accuracy: 8)
    }

    func testClearPartDoesNotGrowTheSheet() {
        let backing = StickerBacking(width: 12, smoothness: 1)
        let size = CGSize(width: 260, height: 180)
        let alone = SketchGroupRenderer.silhouetteLines(
            parts: [SketchPart(cleanRect(x: 30, y: 30, width: 50, height: 40))],
            backing: backing,
            size: size
        )
        var clear = RoughView().roughness(0).bowing(0).stroke(Color.clear).fill(Color.clear)
        clear = clear.draw(Rectangle(x: 140, y: 20, width: 80, height: 80))
        let withClear = SketchGroupRenderer.silhouetteLines(
            parts: [
                SketchPart(cleanRect(x: 30, y: 30, width: 50, height: 40)),
                SketchPart(clear)
            ],
            backing: backing,
            size: size
        )
        XCTAssertEqual(bounds(alone.flatMap(\.points)).width, bounds(withClear.flatMap { $0.points }).width, accuracy: 1)
    }

    func testGroupOfOneMatchesTheSingleShapeMargin() throws {
        let size = CGSize(width: 220, height: 160)
        let shape = Rectangle(x: 40, y: 36, width: 100, height: 60)
        var options = Options()
        options.roughness = 0
        options.bowing = 0
        options.maxRandomnessOffset = 0
        options.strokeWidth = 4
        options.seed = 1
        options.fill = .clear
        options.stickerBacking = StickerBacking(width: 16, smoothness: 1)
        let generator = Engine.shared.generator(size: size)
        let drawing = try XCTUnwrap(generator.generate(drawable: shape, options: options))
        let single = try XCTUnwrap(
            SwiftUIRenderer().commands(for: drawing, options: options, in: size).first
        )
        var view = RoughView()
        view.options = options
        view.drawables = [shape]
        let lines = SketchGroupRenderer.silhouetteLines(
            parts: [SketchPart(view)],
            backing: StickerBacking(width: 16, smoothness: 1),
            size: size
        )
        let hull = bounds(lines.flatMap(\.points))
        // The group hull includes half the stroke. The single sheet adds the rest.
        XCTAssertEqual(single.path.boundingRect.minX, hull.minX - 16, accuracy: 4)
        XCTAssertEqual(single.path.boundingRect.maxX, hull.maxX + 16, accuracy: 4)
    }

    func testSharedBackingHasNoHaloBetweenOverlappingFills() throws {
        let slate = Color(red: 0.22, green: 0.31, blue: 0.39)
        let card = ZStack {
            slate
            groupPair
                .frame(width: 220, height: 160)
        }
        .frame(width: 260, height: 200)
        let image = try render(card, scale: 1)
        // The group sits in a 20pt margin. The inner rect starts at card x 90.
        // x 78 is on the outer blue fill, beside the inner shape, where a
        // per-shape halo would be white.
        let seam = try pixel(image, x: 78, y: 96)
        XCTAssertGreaterThan(seam.blue, seam.red + 30, "seam \(seam)")
        XCTAssertLessThan(seam.red, 80, "seam \(seam)")
        let margin = try pixel(image, x: 30, y: 96)
        XCTAssertGreaterThan(margin.red, 200, "margin \(margin)")
        XCTAssertGreaterThan(margin.green, 200, "margin \(margin)")
        XCTAssertGreaterThan(margin.blue, 200, "margin \(margin)")
        let outside = try pixel(image, x: 6, y: 6)
        XCTAssertLessThan(outside.red, 90, "outside \(outside)")
        XCTAssertGreaterThan(outside.blue, outside.red, "outside \(outside)")
    }

    func testTornGroupIsDeterministic() throws {
        let first = try render(tornPair.frame(width: 220, height: 160).background(Color.white), scale: 1)
        let second = try render(tornPair.frame(width: 220, height: 160).background(Color.white), scale: 1)
        let firstPNG = UIImage(cgImage: first).pngData()
        let secondPNG = UIImage(cgImage: second).pngData()
        XCTAssertEqual(firstPNG, secondPNG)
    }

    private var groupPair: some View {
        SketchGroup {
            RoughView()
                .roughness(0)
                .bowing(0)
                .fillStyle(.solid)
                .strokeWidth(4)
                .stroke(Color(red: 0.10, green: 0.22, blue: 0.55))
                .fill(Color(red: 0.10, green: 0.22, blue: 0.55))
                .seed(3)
                .draw(Rectangle(x: 20, y: 30, width: 120, height: 90))
            RoughView()
                .roughness(0)
                .bowing(0)
                .fillStyle(.solid)
                .strokeWidth(4)
                .stroke(Color(red: 0.75, green: 0.28, blue: 0.22))
                .fill(Color(red: 0.75, green: 0.28, blue: 0.22))
                .seed(3)
                .draw(Rectangle(x: 70, y: 50, width: 70, height: 50))
        }
        .stickerBacking(width: 14, smoothness: 1, color: Color.white)
        .seed(3)
    }

    private var tornPair: some View {
        SketchGroup {
            RoughView()
                .roughness(0)
                .bowing(0)
                .strokeWidth(3)
                .stroke(Color.black)
                .fill(Color(red: 0.20, green: 0.48, blue: 0.78))
                .seed(11)
                .draw(Circle(x: 70, y: 70, diameter: 70))
            SketchPart(
                RoughView()
                    .roughness(0)
                    .bowing(0)
                    .strokeWidth(3)
                    .stroke(Color.black)
                    .fill(Color(red: 0.86, green: 0.36, blue: 0.28))
                    .seed(11)
                    .draw(Circle(x: 70, y: 70, diameter: 56))
            )
            .sketchOffset(x: 36, y: 8)
        }
        .stickerBacking(
            width: 12,
            smoothness: 0.4,
            edge: .torn(StickerTear(depth: 5, length: 14, jaggedness: 0.3)),
            color: Color.white
        )
        .seed(11)
    }

    private func cleanRect(x: Float, y: Float, width: Float, height: Float) -> RoughView {
        RoughView()
            .roughness(0)
            .bowing(0)
            .maxRandomnessOffset(0)
            .strokeWidth(4)
            .stroke(Color.black)
            .fill(Color.clear)
            .seed(1)
            .draw(Rectangle(x: x, y: y, width: width, height: height))
    }

    private func square(_ rect: CGRect, shape: Int) -> SilhouetteRing {
        SilhouetteRing(
            points: [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY)
            ],
            shape: shape,
            isHole: false
        )
    }

    /// Even-odd across every returned ring. A hole ring counts, so its interior is uncovered.
    private func sheetCovers(_ point: CGPoint, _ rings: [SilhouetteRing]) -> Bool {
        rings.filter { contains(point, $0.points) }.count % 2 == 1
    }

    private func covered(_ point: CGPoint, _ rings: [SilhouetteRing]) -> Bool {
        let shapes = Dictionary(grouping: rings, by: \.shape)
        for group in shapes.values {
            let hits = group.filter { contains(point, $0.points) }.count
            if hits % 2 == 1 { return true }
        }
        return false
    }

    private func contains(_ point: CGPoint, _ ring: [CGPoint]) -> Bool {
        var inside = false
        var previous = ring.count - 1
        for index in ring.indices {
            let currentY = ring[index].y
            let previousY = ring[previous].y
            if (currentY > point.y) != (previousY > point.y) {
                let x = (ring[previous].x - ring[index].x) * (point.y - currentY)
                    / (previousY - currentY) + ring[index].x
                if point.x < x { inside.toggle() }
            }
            previous = index
        }
        return inside
    }

    private func bounds(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var rect = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() {
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        return rect
    }

    private func render<V: View>(_ view: V, scale: CGFloat = 2) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
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
