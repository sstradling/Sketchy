import CoreGraphics
import SwiftUI
import XCTest
@testable import Sketchy

/// Paper backing behind a sketch. Geometry is checked on the render commands
/// so a disabled backing cannot change the existing stroke or fill output.
@MainActor
final class StickerBackingTests: XCTestCase {

    func testDisabledBackingMatchesTheUnbackedCommands() throws {
        let size = CGSize(width: 220, height: 180)
        var options = cleanOptions()
        options.strokeJoin = .curvedBevel(bulge: 0.65)
        options.strokeMiterLimit = 3
        options.fill = .systemRed
        options.fillStyle = .solid
        let drawing = try drawing(Polygon(points: star(cx: 110, cy: 90, outer: 70, inner: 30)), options: options, size: size)

        let plain = SwiftUIRenderer().commands(for: drawing, options: options, in: size)
        var backed = options
        backed.stickerBacking = nil
        let again = SwiftUIRenderer().commands(for: drawing, options: backed, in: size)
        XCTAssertEqual(plain.count, again.count)
        for (left, right) in zip(plain, again) {
            XCTAssertEqual(left.path.boundingRect, right.path.boundingRect)
            XCTAssertEqual(left.miterLimit, right.miterLimit)
            XCTAssertEqual(left.join, right.join)
        }
        XCTAssertFalse(plain.isEmpty)
    }

    func testZeroWidthDrawsNoPaper() throws {
        let size = CGSize(width: 200, height: 160)
        var options = cleanOptions()
        let drawing = try drawing(Rectangle(x: 40, y: 30, width: 100, height: 70), options: options, size: size)
        let plain = SwiftUIRenderer().commands(for: drawing, options: options, in: size)
        options.stickerBacking = StickerBacking(width: 0, smoothness: 1, edge: .torn())
        let backed = SwiftUIRenderer().commands(for: drawing, options: options, in: size)
        XCTAssertEqual(plain.count, backed.count)
    }

    func testBackingDoesNotChangeGeneratedGeometry() throws {
        let size = CGSize(width: 200, height: 160)
        var plain = cleanOptions()
        plain.seed = 19
        plain.roughness = 1.4
        var backed = plain
        backed.stickerBacking = StickerBacking(width: 14, smoothness: 0.7, edge: .torn(StickerTear(depth: 6)))

        let generator = Engine().generator(size: size)
        let shape = Circle(x: 100, y: 80, diameter: 90)
        let left = try XCTUnwrap(generator.generate(drawable: shape, options: plain))
        let right = try XCTUnwrap(generator.generate(drawable: shape, options: backed))
        XCTAssertEqual(left.sets.count, right.sets.count)
        for (a, b) in zip(left.sets, right.sets) {
            XCTAssertEqual(a.type, b.type)
            XCTAssertEqual(a.operations.count, b.operations.count)
        }
    }

    func testClosedRectangleGrowsByTheMarginPastTheStroke() throws {
        let size = CGSize(width: 220, height: 180)
        var options = cleanOptions()
        options.strokeWidth = 4
        options.stickerBacking = StickerBacking(width: 16)
        let drawing = try drawing(Rectangle(x: 40, y: 36, width: 100, height: 60), options: options, size: size)
        let commands = SwiftUIRenderer().commands(for: drawing, options: options, in: size)
        let paper = try XCTUnwrap(commands.first)
        guard case .fill = paper.style else {
            return XCTFail("Closed contour should fill a sheet, not only stroke one")
        }
        let bounds = paper.path.boundingRect
        // Centerline is the rectangle. The sheet reaches width + strokeWidth/2 past it.
        XCTAssertEqual(bounds.minX, 22, accuracy: 3)
        XCTAssertEqual(bounds.minY, 18, accuracy: 3)
        XCTAssertEqual(bounds.maxX, 158, accuracy: 3)
        XCTAssertEqual(bounds.maxY, 114, accuracy: 3)

        let plain = SwiftUIRenderer().commands(
            for: drawing,
            options: cleanOptions(strokeWidth: 4),
            in: size
        )
        XCTAssertEqual(commands.count, plain.count + 1)
        for (backed, original) in zip(commands.dropFirst(), plain) {
            XCTAssertEqual(backed.path.boundingRect, original.path.boundingRect)
        }
    }

    func testSmoothRectangleKeepsASharpCorner() throws {
        let size = CGSize(width: 220, height: 180)
        let shape = Rectangle(x: 40, y: 36, width: 100, height: 60)
        let sharp = try paperPath(shape, backing: StickerBacking(width: 18, smoothness: 1, edge: .smooth), size: size)
        let rounded = try paperPath(shape, backing: StickerBacking(width: 18, smoothness: 1, edge: .fullySmooth()), size: size)
        let sharpGap = cornerGap(sharp)
        let roundedGap = cornerGap(rounded)
        XCTAssertLessThan(sharpGap, 5, "smooth corner gap \(sharpGap)")
        XCTAssertGreaterThan(roundedGap, sharpGap + 6, "fully smooth gap \(roundedGap)")

        let square = Sketchy.Path(d: "M40 36 H150 V146 H40 Z")
        let pathSheet = try paperPath(
            square,
            backing: StickerBacking(width: 32, smoothness: 1, edge: .smooth),
            size: CGSize(width: 220, height: 220)
        )
        XCTAssertLessThan(cornerGap(pathSheet), 5, "svg square corner gap")

        var grouped = RoughView().roughness(0).bowing(0).maxRandomnessOffset(0).strokeWidth(2).seed(9)
        grouped = grouped.draw(Sketchy.Path(d: "M40 36 H150 V146 H40 Z M78 74 H112 V112 H78 Z"))
        let groupBacking = StickerBacking(width: 32, smoothness: 1, edge: .smooth)
        let lines = SketchGroupRenderer.silhouetteLines(
            parts: [SketchPart(grouped)],
            backing: groupBacking,
            size: CGSize(width: 240, height: 240)
        )
        let sheet = StickerBackingBuilder.commands(
            for: lines,
            outward: groupBacking.width,
            backing: groupBacking,
            seed: 9
        )
        let groupGap = cornerGap(sheet[0].path)
        XCTAssertLessThan(groupGap, 6, "group square corner gap \(groupGap)")
    }

    func testWiderBackingIsLarger() throws {
        let size = CGSize(width: 220, height: 180)
        let shape = Rectangle(x: 40, y: 36, width: 100, height: 60)
        let narrow = try paperBounds(shape, width: 8, size: size)
        let wide = try paperBounds(shape, width: 22, size: size)
        XCTAssertLessThan(wide.minX, narrow.minX - 8)
        XCTAssertGreaterThan(wide.maxX, narrow.maxX + 8)
        XCTAssertLessThan(wide.minY, narrow.minY - 8)
        XCTAssertGreaterThan(wide.maxY, narrow.maxY + 8)
    }

    func testSmoothnessRemovesWobbleAndKeepsTheStar() throws {
        let size = CGSize(width: 260, height: 240)
        var options = Options()
        options.seed = 11
        options.roughness = 2.4
        options.maxRandomnessOffset = 3.2
        options.bowing = 1
        options.strokeWidth = 2
        options.fill = .clear
        let points = star(cx: 130, cy: 120, outer: 78, inner: 32)
        let ideal = points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        let shape = Polygon(points: points)

        options.stickerBacking = StickerBacking(width: 12, smoothness: 0)
        let roughDrawing = try drawing(shape, options: options, size: size)
        let rough = try onlyClosed(StickerBackingBuilder.centerlines(
            for: roughDrawing, options: options, backing: options.stickerBacking!, transform: nil
        ))

        options.stickerBacking = StickerBacking(width: 12, smoothness: 1)
        let smoothDrawing = try drawing(shape, options: options, size: size)
        let smooth = try onlyClosed(StickerBackingBuilder.centerlines(
            for: smoothDrawing, options: options, backing: options.stickerBacking!, transform: nil
        ))

        let roughDistance = meanEdgeDistance(rough, to: ideal)
        let smoothDistance = meanEdgeDistance(smooth, to: ideal)
        XCTAssertGreaterThan(roughDistance, 1)
        XCTAssertLessThan(smoothDistance, roughDistance * 0.45)
        XCTAssertGreaterThan(radiusRatio(smooth), 1.7)
    }

    func testTornEdgeIsSeededAndDiffersFromSmooth() throws {
        let size = CGSize(width: 220, height: 180)
        var options = cleanOptions()
        options.seed = 23
        options.roughness = 1.1
        let shape = Circle(x: 110, y: 90, diameter: 100)
        options.stickerBacking = StickerBacking(width: 14, smoothness: 0.45, edge: .smooth)
        let smooth = try paperPath(shape, options: options, size: size)

        options.stickerBacking = StickerBacking(
            width: 14,
            smoothness: 0.45,
            edge: .torn(StickerTear(depth: 7, length: 14, jaggedness: 0.4))
        )
        let torn = try paperPath(shape, options: options, size: size)
        let again = try paperPath(shape, options: options, size: size)
        XCTAssertEqual(samples(torn), samples(again))
        XCTAssertNotEqual(samples(torn), samples(smooth))

        options.seed = 99
        let otherSeed = try paperPath(shape, options: options, size: size)
        XCTAssertNotEqual(samples(torn), samples(otherSeed))
    }

    func testOpenLineIsARibbonNotAFilledSheet() throws {
        let size = CGSize(width: 220, height: 120)
        var options = cleanOptions()
        options.strokeWidth = 3
        options.fill = .clear
        options.stickerBacking = StickerBacking(width: 10, smoothness: 0.2)
        let drawing = try drawing(Line(from: Point(x: 20, y: 60), to: Point(x: 190, y: 64)), options: options, size: size)
        let backed = SwiftUIRenderer().commands(for: drawing, options: options, in: size)
        var plainOptions = options
        plainOptions.stickerBacking = nil
        let plain = SwiftUIRenderer().commands(for: drawing, options: plainOptions, in: size)
        let extra = backed.count - plain.count
        XCTAssertGreaterThan(extra, 0)
        for command in backed.prefix(extra) {
            guard case .stroke(_, let lineWidth) = command.style else {
                return XCTFail("Open contour should be a paper ribbon")
            }
            XCTAssertEqual(lineWidth, 23, accuracy: 0.01)
        }
    }

    func testLegacyClosedShapeStaysARibbon() throws {
        let size = CGSize(width: 200, height: 160)
        var options = cleanOptions()
        options.strokeContinuity = .legacy
        options.fill = .clear
        let drawing = try drawing(Rectangle(x: 30, y: 30, width: 90, height: 70), options: options, size: size)
        let plain = SwiftUIRenderer().commands(for: drawing, options: options, in: size)
        options.stickerBacking = StickerBacking(width: 8)
        let backed = SwiftUIRenderer().commands(for: drawing, options: options, in: size)
        let extra = backed.count - plain.count
        XCTAssertGreaterThanOrEqual(extra, 4)
        for command in backed.prefix(extra) {
            guard case .stroke = command.style else {
                return XCTFail("Legacy edges are open strokes, so the paper is a ribbon")
            }
        }
    }

    func testCompoundHoleKeepsAnOpeningAndAMargin() throws {
        let size = CGSize(width: 160, height: 160)
        var options = cleanOptions()
        options.strokeWidth = 2
        options.fill = .clear
        options.roughness = 0.4
        options.stickerBacking = StickerBacking(width: 10, smoothness: 0.85)
        let path = "M10 10 H110 V110 H10 Z M40 40 H80 V80 H40 Z"
        let drawing = try drawing(Path(d: path), options: options, size: size)
        let commands = SwiftUIRenderer().commands(for: drawing, options: options, in: size)
        let paper = try XCTUnwrap(commands.first)
        guard case .fill = paper.style else {
            return XCTFail("A closed compound path should fill one sheet")
        }
        let outline = paper.path.cgPath
        let bounds = paper.path.boundingRect
        let hole = CGPoint(x: bounds.midX, y: bounds.midY)
        XCTAssertFalse(outline.contains(hole, using: .evenOdd))
        let material = CGPoint(x: bounds.minX + bounds.width * 0.12, y: bounds.midY)
        XCTAssertTrue(outline.contains(material, using: .evenOdd))
        XCTAssertGreaterThan(bounds.width, 100)
    }

    func testConcaveStarOffsetDoesNotExplode() throws {
        let size = CGSize(width: 240, height: 220)
        var options = cleanOptions()
        options.roughness = 1.3
        options.seed = 4
        options.stickerBacking = StickerBacking(width: 14, smoothness: 0.15)
        let drawing = try drawing(
            Polygon(points: star(cx: 120, cy: 110, outer: 80, inner: 28)),
            options: options,
            size: size
        )
        let commands = SwiftUIRenderer().commands(for: drawing, options: options, in: size)
        let paper = try XCTUnwrap(commands.first)
        let bounds = paper.path.boundingRect
        XCTAssertTrue(bounds.width.isFinite && bounds.height.isFinite)
        XCTAssertLessThan(bounds.width, 280)
        XCTAssertGreaterThan(bounds.width, 140)
        let ratio = radiusRatio(samples(paper.path))
        XCTAssertGreaterThan(ratio, 1.35)
    }

    func testSmoothEggPaperIsACurveAndStarKeepsCorners() throws {
        let eggOptions = cleanOptions()
        var eggBacking = eggOptions
        eggBacking.strokeWidth = 2
        eggBacking.stickerBacking = StickerBacking(width: 22, smoothness: 1)
        let eggSize = CGSize(width: 240, height: 280)
        let eggPath = try paperPath(
            EggShape(x: 120, y: 140, width: 90, height: 140, tilt: 0.42),
            options: eggBacking,
            size: eggSize
        )
        let eggKinds = elementKinds(eggPath)
        XCTAssertGreaterThan(eggKinds.curves, 12)
        XCTAssertEqual(eggKinds.lines, 0)
        let eggTurns = turningSamples(eggPath, spacing: 8)
        XCTAssertLessThan(eggTurns.max() ?? 1, 0.7)
        XCTAssertEqual(isolatedFacets(eggTurns), 0)

        var starOptions = cleanOptions()
        starOptions.stickerBacking = StickerBacking(width: 12, smoothness: 1)
        let starPath = try paperPath(
            Polygon(points: star(cx: 110, cy: 100, outer: 70, inner: 28)),
            options: starOptions,
            size: CGSize(width: 220, height: 200)
        )
        let starTurns = turningSamples(starPath, spacing: 6)
        XCTAssertGreaterThan(starTurns.max() ?? 0, 0.85)
        XCTAssertGreaterThan(isolatedFacets(starTurns), 3)

        var tornOptions = eggBacking
        tornOptions.stickerBacking = StickerBacking(
            width: 22,
            smoothness: 1,
            edge: .torn(StickerTear(depth: 8, length: 16, jaggedness: 0.4))
        )
        let tornPath = try paperPath(
            EggShape(x: 120, y: 140, width: 90, height: 140, tilt: 0.42),
            options: tornOptions,
            size: eggSize
        )
        XCTAssertEqual(elementKinds(tornPath).curves, 0)
        XCTAssertGreaterThan(elementKinds(tornPath).lines, 8)
    }

    func testFullySmoothEggHasNoFacetSpikesAndRoundsAStar() throws {
        let size = CGSize(width: 240, height: 280)
        func backedEgg(_ edge: StickerEdge) throws -> SwiftUI.Path {
            var options = cleanOptions()
            options.strokeWidth = 2
            options.stickerBacking = StickerBacking(width: 22, smoothness: 1, edge: edge)
            return try paperPath(
                EggShape(x: 120, y: 140, width: 86, height: 124, tilt: 0.42),
                options: options,
                size: size
            )
        }
        let preserving = try backedEgg(.smooth)
        let rounded = try backedEgg(.fullySmooth())
        let again = try backedEgg(.fullySmooth())
        XCTAssertEqual(samples(rounded), samples(again))
        XCTAssertEqual(isolatedFacets(turningSamples(rounded, spacing: 6)), 0)
        XCTAssertLessThan(
            turningSamples(rounded, spacing: 6).max() ?? 1,
            (turningSamples(preserving, spacing: 6).max() ?? 0) * 0.75
        )
        XCTAssertGreaterThan(elementKinds(rounded).curves, 12)

        let starSize = CGSize(width: 220, height: 200)
        let starShape = Polygon(points: star(cx: 110, cy: 100, outer: 70, inner: 28))
        func backedStar(_ edge: StickerEdge) throws -> SwiftUI.Path {
            var options = cleanOptions()
            options.stickerBacking = StickerBacking(width: 12, smoothness: 1, edge: edge)
            return try paperPath(starShape, options: options, size: starSize)
        }
        let sharp = turningSamples(try backedStar(.smooth), spacing: 6).max() ?? 0
        let soft = turningSamples(try backedStar(.fullySmooth()), spacing: 6).max() ?? 0
        XCTAssertGreaterThan(sharp, 0.85)
        XCTAssertLessThan(soft, sharp - 0.25)
        XCTAssertEqual(isolatedFacets(turningSamples(try backedStar(.fullySmooth()), spacing: 6)), 0)
    }

    /// The fully smooth preview egg grew an inward bite on the right edge,
    /// at the cubic seam. A narrow radial dip there must stay gone.
    func testFullySmoothEggHasNoRightSideNotch() throws {
        var options = Options()
        options.roughness = 1.45
        options.maxRandomnessOffset = 2.4
        options.bowing = 1
        options.seed = 17
        options.strokeWidth = 2
        options.fillStyle = .hachure
        options.fillAngle = 0
        options.fillSpacing = 3
        options.stickerBacking = StickerBacking(width: 22, smoothness: 1, edge: .fullySmooth())
        let size = CGSize(width: 240, height: 300)
        let shape = EggShape(x: 100, y: 112, width: 86, height: 124, tilt: 0.42)
        let drawing = try drawing(shape, options: options, size: size)
        let commands = SwiftUIRenderer().commands(for: drawing, options: options, in: size)
        let paper = try XCTUnwrap(commands.first)
        guard case .fill = paper.style else {
            return XCTFail("fully smooth egg should be a filled sheet, not an open ribbon with a cap seam")
        }
        let path = paper.path
        let dip = narrowRadialDip(path, shoulder: 0.18)
        let reversal = rightSilhouetteReversal(path)
        XCTAssertLessThan(dip, 1.25, "right-side notch is \(dip) points deep")
        XCTAssertLessThan(reversal, 1.25, "right-edge shelf is \(reversal) points")
        XCTAssertEqual(isolatedFacets(turningSamples(path, spacing: 4)), 0)
    }

    /// Fully smooth compound shapes keep an open hole and a continuous outer edge.
    func testFullySmoothCompoundKeepsHoleAndContinuousEdge() throws {
        var options = Options()
        options.roughness = 1.2
        options.seed = 9
        options.strokeWidth = 2
        options.fill = .clear
        options.stickerBacking = StickerBacking(width: 12, smoothness: 0.9, edge: .fullySmooth())
        let size = CGSize(width: 180, height: 180)
        let shape = Sketchy.Path(d: "M16 16 H144 V144 H16 Z M50 50 H110 V110 H50 Z")
        let drawing = try drawing(shape, options: options, size: size)
        let commands = SwiftUIRenderer().commands(for: drawing, options: options, in: size)
        let paper = try XCTUnwrap(commands.first)
        guard case .fill = paper.style else {
            return XCTFail("fully smooth compound backing should be one filled sheet")
        }
        XCTAssertNil(commands.first?.clipPath)
        XCTAssertGreaterThan(elementKinds(paper.path).curves, 8)
        let bounds = paper.path.boundingRect
        let hole = CGPoint(x: bounds.midX, y: bounds.midY)
        XCTAssertFalse(paper.path.cgPath.contains(hole, using: .evenOdd), "the compound hole should stay open")
        XCTAssertTrue(
            paper.path.cgPath.contains(CGPoint(x: bounds.minX + 18, y: bounds.midY), using: .evenOdd)
        )
        let outer = firstSubpath(paper.path)
        XCTAssertEqual(isolatedFacets(turningSamples(outer, spacing: 6)), 0)
        XCTAssertLessThan(rightSilhouetteReversal(outer), 2.5)
    }

    func testTextureIsSeededClippedAndOptional() throws {
        let size = CGSize(width: 180, height: 160)
        var options = cleanOptions()
        options.strokeWidth = 2
        options.stickerBacking = StickerBacking(width: 12, smoothness: 1, color: .white, texture: nil)
        let plain = try commands(Rectangle(x: 30, y: 28, width: 100, height: 70), options: options, size: size)
        let bare = try commands(Rectangle(x: 30, y: 28, width: 100, height: 70), options: cleanOptions(strokeWidth: 2), size: size)
        XCTAssertEqual(plain.count, bare.count + 1)

        options.stickerBacking = StickerBacking(
            width: 12,
            smoothness: 1,
            color: UIColor(red: 0.95, green: 0.90, blue: 0.75, alpha: 1),
            texture: StickerTexture(amount: 0.5, scale: 10, seed: 5)
        )
        let tinted = try commands(Rectangle(x: 30, y: 28, width: 100, height: 70), options: options, size: size)
        let again = try commands(Rectangle(x: 30, y: 28, width: 100, height: 70), options: options, size: size)
        let fibers = tinted.filter { $0.clipPath != nil }
        XCTAssertFalse(fibers.isEmpty)
        XCTAssertEqual(fibers.count, again.filter { $0.clipPath != nil }.count)
        XCTAssertEqual(samples(fibers[0].path), samples(again.first { $0.clipPath != nil }!.path))
        XCTAssertEqual(fibers[0].clipPath?.boundingRect, tinted[0].path.boundingRect)

        options.stickerBacking = StickerBacking(
            width: 12,
            smoothness: 1,
            texture: StickerTexture(amount: 0.5, scale: 10, seed: 9)
        )
        let other = try commands(Rectangle(x: 30, y: 28, width: 100, height: 70), options: options, size: size)
        XCTAssertNotEqual(
            samples(fibers[0].path),
            samples(other.first { $0.clipPath != nil }!.path)
        )

        let view = RoughView().stickerBacking(
            width: 10,
            color: Color(red: 0.2, green: 0.4, blue: 0.8),
            texture: .paper(seed: 3)
        )
        XCTAssertEqual(view.options.stickerBacking?.texture?.seed, 3)
        XCTAssertEqual(view.options.stickerBacking?.texture?.amount, 0.45)
        var red: CGFloat = 0
        view.options.stickerBacking?.color.getRed(&red, green: nil, blue: nil, alpha: nil)
        XCTAssertEqual(red, 0.2, accuracy: 0.02)
    }

    func testImageTextureIsMaskedAndLeavesFibersAlone() throws {
        let size = CGSize(width: 180, height: 180)
        let weave = try weaveImage()
        var options = Options()
        options.roughness = 1.2
        options.seed = 9
        options.strokeWidth = 2
        options.fill = .clear
        options.stickerBacking = StickerBacking(width: 12, smoothness: 0.9, edge: .fullySmooth())
        let plain = try commands(
            Sketchy.Path(d: "M16 16 H144 V144 H16 Z M50 50 H110 V110 H50 Z"),
            options: options,
            size: size
        )
        XCTAssertTrue(plain.allSatisfy { $0.stickerImage == nil })

        let image = StickerImage(image: weave, placement: .tile, scale: 24, opacity: 0.6)
        options.stickerBacking = StickerBacking(
            width: 12,
            smoothness: 0.9,
            edge: .fullySmooth(),
            image: image
        )
        let painted = try commands(
            Sketchy.Path(d: "M16 16 H144 V144 H16 Z M50 50 H110 V110 H50 Z"),
            options: options,
            size: size
        )
        let masks = painted.filter { $0.stickerImage != nil }
        XCTAssertEqual(masks.count, 1)
        XCTAssertEqual(masks[0].stickerImage?.placement, .tile)
        XCTAssertEqual(masks[0].stickerImage?.scale, 24)
        XCTAssertEqual(masks[0].stickerImage?.opacity, 0.6)
        XCTAssertEqual(masks[0].fillRule, .evenOdd)
        let bounds = painted[0].path.boundingRect
        let hole = CGPoint(x: bounds.midX, y: bounds.midY)
        XCTAssertFalse(masks[0].path.cgPath.contains(hole, using: .evenOdd))
        XCTAssertTrue(masks[0].path.cgPath.contains(CGPoint(x: bounds.minX + 16, y: bounds.midY), using: .evenOdd))
        XCTAssertEqual(masks[0].path.boundingRect, painted[0].path.boundingRect)

        options.stickerBacking = StickerBacking(
            width: 12,
            smoothness: 0.4,
            edge: .torn(StickerTear(depth: 8, length: 16, jaggedness: 0.4)),
            image: StickerImage(image: weave, placement: .stretch, scale: 1.4, opacity: 1)
        )
        let torn = try commands(
            Sketchy.Path(d: "M16 16 H144 V144 H16 Z"),
            options: options,
            size: size
        )
        let tornImage = try XCTUnwrap(torn.first { $0.stickerImage != nil })
        XCTAssertEqual(tornImage.stickerImage?.placement, .stretch)
        XCTAssertEqual(tornImage.stickerImage?.resolvedFitScale, 1.4)
        XCTAssertEqual(tornImage.path.boundingRect, torn[0].path.boundingRect)

        options.stickerBacking = StickerBacking(width: 12, image: StickerImage(image: weave, opacity: 0))
        let hidden = try commands(Rectangle(x: 30, y: 28, width: 100, height: 70), options: options, size: size)
        XCTAssertTrue(hidden.allSatisfy { $0.stickerImage == nil })

        let natural = StickerImage(image: weave)
        XCTAssertEqual(natural.resolvedTileWidth, max(4, weave.size.width))
        let coarse = StickerImagePainter.tileWidth(
            StickerImage(image: weave, scale: 4),
            in: CGRect(x: 0, y: 0, width: 400, height: 400)
        )
        XCTAssertGreaterThan(coarse, 4)

        var hashed = Options()
        hashed.stickerBacking = StickerBacking(width: 8, image: StickerImage(image: weave, scale: 20))
        let firstHash = hashed.cacheHash
        hashed.stickerBacking = StickerBacking(width: 8, image: StickerImage(image: weave, scale: 40))
        XCTAssertNotEqual(firstHash, hashed.cacheHash)
        hashed.stickerBacking = StickerBacking(width: 8, texture: .paper(seed: 3))
        XCTAssertNil(hashed.stickerBacking?.image)
        XCTAssertEqual(hashed.stickerBacking?.texture?.seed, 3)
    }

    func testImageTexturePixelsStayOutOfTheHoleAndOffTheMargin() throws {
        let red = solidImage(UIColor(red: 0.85, green: 0.15, blue: 0.2, alpha: 1))
        let card = ZStack {
            Color(red: 0.22, green: 0.31, blue: 0.39)
            RoughView()
                .stroke(Color(red: 0.12, green: 0.14, blue: 0.18))
                .strokeWidth(2)
                .roughness(0.4)
                .seed(9)
                .stickerBacking(
                    width: 10,
                    smoothness: 1,
                    edge: .smooth,
                    image: StickerImage(image: red, placement: .stretch, opacity: 1)
                )
                .draw(Sketchy.Path(d: "M24 24 H156 V156 H24 Z M64 64 H116 V116 H64 Z"))
                .frame(width: 140, height: 140)
        }
        .frame(width: 180, height: 180)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 180, height: 180)
        renderer.isOpaque = true
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        func isRed(_ sample: RGBA) -> Bool {
            sample.red > 140 && sample.green < 100 && sample.blue < 120
        }
        // The 140-point view is centered in the 180-point card, so view (x, y) is card (x + 20, y + 20).
        XCTAssertFalse(isRed(try pixel(image, x: 4, y: 4)), "image spilled past the card")
        XCTAssertFalse(isRed(try pixel(image, x: 110, y: 110)), "image spilled into the hole")
        var sheet = false
        for x in 30...50 where isRed(try pixel(image, x: x, y: 110)) {
            sheet = true
        }
        XCTAssertTrue(sheet, "image should cover the sheet margin")
    }

    func testWeaveFixtureDecodesAndMatchesTheSyntheticChecker() throws {
        let image = try weaveImage()
        XCTAssertEqual(image.size, CGSize(width: 16, height: 16))
        let decoded = try XCTUnwrap(StickerImage(data: try weaveData(), placement: .fill, scale: 1.2))
        XCTAssertEqual(decoded.placement, .fill)
        XCTAssertEqual(decoded.resolvedFitScale, 1.2)
        guard let pixels = image.cgImage else {
            return XCTFail("weave has no pixels")
        }
        guard let data = pixels.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            return XCTFail("weave has no bytes")
        }
        let rose = (bytes[0], bytes[1], bytes[2])
        XCTAssertGreaterThan(rose.0, 180)
        XCTAssertLessThan(rose.1, 100)
    }

    func testCacheHashIncludesBacking() {
        var options = Options()
        let plain = options.cacheHash
        options.stickerBacking = StickerBacking(width: 8)
        XCTAssertNotEqual(plain, options.cacheHash)
        options.stickerBacking = StickerBacking(width: 8, smoothness: 0.5)
        let smooth = options.cacheHash
        options.stickerBacking = StickerBacking(width: 8, smoothness: 0.5, edge: .torn())
        XCTAssertNotEqual(smooth, options.cacheHash)
    }

    func testModifierStoresBacking() {
        let view = RoughView().stickerBacking(width: 9, smoothness: 0.4, edge: .torn())
        XCTAssertEqual(view.options.stickerBacking?.width, 9)
        XCTAssertEqual(view.options.stickerBacking?.smoothness, 0.4)
        guard case .torn = view.options.stickerBacking?.edge else {
            return XCTFail("Expected a torn edge")
        }
        let cleared = view.stickerBacking(nil)
        XCTAssertNil(cleared.options.stickerBacking)
    }

    func testMarginSitsOutsideTheInkAndFillStaysOnTop() throws {
        let view = RoughView()
            .fill(UIColor.systemRed)
            .fillStyle(.solid)
            .stroke(UIColor.black)
            .strokeWidth(4)
            .roughness(0)
            .bowing(0)
            .maxRandomnessOffset(0)
            .seed(3)
            .stickerBacking(width: 16)
            .draw(Rectangle(x: 40, y: 40, width: 100, height: 60))
            .frame(width: 200, height: 160)
            .background(Color.blue)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 200, height: 160)
        renderer.isOpaque = true
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        let center = try pixel(image, x: 90, y: 70)
        let margin = try pixel(image, x: 28, y: 70)
        let outside = try pixel(image, x: 6, y: 6)
        XCTAssertGreaterThan(center.red, 180)
        XCTAssertLessThan(center.blue, 80)
        XCTAssertGreaterThan(margin.red, 220)
        XCTAssertGreaterThan(margin.green, 220)
        XCTAssertGreaterThan(margin.blue, 220)
        XCTAssertGreaterThan(outside.blue, 180)
        XCTAssertLessThan(outside.red, 80)
    }

    // MARK: - Fixtures

    private func cleanOptions(strokeWidth: Float = 2) -> Options {
        var options = Options()
        options.roughness = 0
        options.bowing = 0
        options.maxRandomnessOffset = 0
        options.strokeWidth = strokeWidth
        options.seed = 1
        options.fill = .clear
        return options
    }

    private func drawing(_ shape: Drawable, options: Options, size: CGSize) throws -> Drawing {
        let generator = Engine().generator(size: size)
        return try XCTUnwrap(generator.generate(drawable: shape, options: options))
    }

    /// Distance from the filled outline's corner to the corner of its bounds.
    /// Control points are not the outline. A square sheet is near 0. A squircle leaves a gap.
    private func cornerGap(_ path: SwiftUI.Path) -> CGFloat {
        let samples = outlineSamples(path)
        guard let first = samples.first else { return .greatestFiniteMagnitude }
        var minX = first.x
        var minY = first.y
        for point in samples {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
        }
        var nearest = CGFloat.greatestFiniteMagnitude
        for point in samples {
            nearest = min(nearest, hypot(point.x - minX, point.y - minY))
        }
        return nearest
    }

    private func outlineSamples(_ path: SwiftUI.Path) -> [CGPoint] {
        var samples: [CGPoint] = []
        var cursor = CGPoint.zero
        path.cgPath.applyWithBlock { element in
            let kind = element.pointee.type
            let points = element.pointee.points
            if kind == .moveToPoint {
                cursor = points[0]
                samples.append(cursor)
            } else if kind == .addLineToPoint {
                samples.append(points[0])
                cursor = points[0]
            } else if kind == .addQuadCurveToPoint {
                samples.append(contentsOf: Self.quadSamples(cursor, points[0], points[1]))
                cursor = points[1]
            } else if kind == .addCurveToPoint {
                samples.append(contentsOf: Self.cubicSamples(cursor, points[0], points[1], points[2]))
                cursor = points[2]
            }
        }
        return samples
    }

    private static func quadSamples(_ start: CGPoint, _ control: CGPoint, _ end: CGPoint) -> [CGPoint] {
        var points: [CGPoint] = []
        for step in 1...8 {
            let t = CGFloat(step) / 8
            let u = 1 - t
            points.append(CGPoint(
                x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
            ))
        }
        return points
    }

    private static func cubicSamples(
        _ start: CGPoint,
        _ control1: CGPoint,
        _ control2: CGPoint,
        _ end: CGPoint
    ) -> [CGPoint] {
        var points: [CGPoint] = []
        for step in 1...8 {
            let t = CGFloat(step) / 8
            let u = 1 - t
            let uu = u * u
            let tt = t * t
            points.append(CGPoint(
                x: uu * u * start.x + 3 * uu * t * control1.x + 3 * u * tt * control2.x + tt * t * end.x,
                y: uu * u * start.y + 3 * uu * t * control1.y + 3 * u * tt * control2.y + tt * t * end.y
            ))
        }
        return points
    }

    private func paperPath(_ shape: Drawable, backing: StickerBacking, size: CGSize) throws -> SwiftUI.Path {
        var options = cleanOptions()
        options.stickerBacking = backing
        let drawing = try drawing(shape, options: options, size: size)
        let command = try XCTUnwrap(
            SwiftUIRenderer().commands(for: drawing, options: options, in: size).first
        )
        return command.path
    }

    private func paperBounds(_ shape: Drawable, width: CGFloat, size: CGSize) throws -> CGRect {
        var options = cleanOptions()
        options.stickerBacking = StickerBacking(width: width)
        let drawing = try drawing(shape, options: options, size: size)
        let command = try XCTUnwrap(
            SwiftUIRenderer().commands(for: drawing, options: options, in: size).first
        )
        return command.path.boundingRect
    }

    private func commands(_ shape: Drawable, options: Options, size: CGSize) throws -> [RoughRenderCommand] {
        let drawing = try drawing(shape, options: options, size: size)
        return SwiftUIRenderer().commands(for: drawing, options: options, in: size)
    }

    private func paperPath(_ shape: Drawable, options: Options, size: CGSize) throws -> SwiftUI.Path {
        let drawing = try drawing(shape, options: options, size: size)
        let command = try XCTUnwrap(
            SwiftUIRenderer().commands(for: drawing, options: options, in: size).first
        )
        return command.path
    }

    private func onlyClosed(_ lines: [StickerBackingBuilder.Centerline]) throws -> [CGPoint] {
        let closed = lines.filter(\.closed)
        XCTAssertEqual(closed.count, 1)
        return try XCTUnwrap(closed.first).points
    }

    private func star(cx: Float, cy: Float, outer: Float, inner: Float) -> [Point] {
        (0..<10).map { index in
            let angle = -Float.pi / 2 + Float(index) * .pi / 5
            let radius = index.isMultiple(of: 2) ? outer : inner
            return Point(x: cx + cos(angle) * radius, y: cy + sin(angle) * radius)
        }
    }

    private func meanEdgeDistance(_ samples: [CGPoint], to polygon: [CGPoint]) -> CGFloat {
        guard !samples.isEmpty, polygon.count >= 3 else { return 0 }
        let total = samples.reduce(CGFloat.zero) { partial, sample in
            var best = CGFloat.greatestFiniteMagnitude
            for index in 0..<polygon.count {
                let start = polygon[index]
                let end = polygon[(index + 1) % polygon.count]
                best = min(best, distance(sample, start, end))
            }
            return partial + best
        }
        return total / CGFloat(samples.count)
    }

    private func distance(_ point: CGPoint, _ start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1e-6 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
    }

    private func radiusRatio(_ points: [CGPoint]) -> CGFloat {
        guard let first = points.first else { return 1 }
        let center = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        let count = CGFloat(points.count)
        let origin = CGPoint(x: center.x / count, y: center.y / count)
        let radii = points.map { hypot($0.x - origin.x, $0.y - origin.y) }
        let maxRadius = radii.max() ?? 1
        let minRadius = max(radii.min() ?? 1, 0.5)
        _ = first
        return maxRadius / minRadius
    }

    private func elementKinds(_ path: SwiftUI.Path) -> (lines: Int, curves: Int) {
        var lines = 0
        var curves = 0
        path.cgPath.applyWithBlock { element in
            switch element.pointee.type {
            case .addLineToPoint:
                lines += 1
            case .addCurveToPoint, .addQuadCurveToPoint:
                curves += 1
            default:
                break
            }
        }
        return (lines, curves)
    }

    private func firstSubpath(_ path: SwiftUI.Path) -> SwiftUI.Path {
        var subpath = SwiftUI.Path()
        var started = false
        var done = false
        path.cgPath.applyWithBlock { element in
            if done { return }
            let values = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                if started {
                    done = true
                    return
                }
                subpath.move(to: values[0])
                started = true
            case .addLineToPoint:
                subpath.addLine(to: values[0])
            case .addQuadCurveToPoint:
                subpath.addQuadCurve(to: values[1], control: values[0])
            case .addCurveToPoint:
                subpath.addCurve(to: values[2], control1: values[0], control2: values[1])
            case .closeSubpath:
                subpath.closeSubpath()
                done = true
            default:
                break
            }
        }
        return subpath
    }

    /// How far a sample sits inside both nearby shoulders. A broad valley
    /// stays near 0. A narrow inward notch, such as the egg's right-edge cusp, does not.
    private func narrowRadialDip(_ path: SwiftUI.Path, shoulder: CGFloat) -> CGFloat {
        let points = resampled(path.cgPath, spacing: 3)
        guard points.count >= 12 else { return 0 }
        let center = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        let count = CGFloat(points.count)
        let origin = CGPoint(x: center.x / count, y: center.y / count)
        let polar = points.map { point -> (angle: CGFloat, radius: CGFloat) in
            (
                atan2(point.y - origin.y, point.x - origin.x),
                hypot(point.x - origin.x, point.y - origin.y)
            )
        }
        func radius(near angle: CGFloat) -> CGFloat {
            var best = polar[0]
            var bestGap = CGFloat.greatestFiniteMagnitude
            for sample in polar {
                var gap = abs(sample.angle - angle)
                if gap > .pi { gap = 2 * .pi - gap }
                if gap < bestGap {
                    bestGap = gap
                    best = sample
                }
            }
            return best.radius
        }
        var worst: CGFloat = 0
        for sample in polar where abs(sample.angle) < 0.55 {
            let left = radius(near: sample.angle - shoulder)
            let right = radius(near: sample.angle + shoulder)
            let dip = min(left, right) - sample.radius
            worst = max(worst, dip)
        }
        return worst
    }

    /// Outward step of the right silhouette away from its single widest point.
    /// A convex cutout is unimodal in x. The egg's seam shelf rises again after the peak.
    private func rightSilhouetteReversal(_ path: SwiftUI.Path) -> CGFloat {
        let points = resampled(path.cgPath, spacing: 2)
        guard points.count >= 12 else { return 0 }
        let origin = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        let count = CGFloat(points.count)
        let center = CGPoint(x: origin.x / count, y: origin.y / count)
        let right = points.filter { $0.x > center.x + 6 }
        guard right.count >= 8 else { return 0 }
        let minY = right.map(\.y).min() ?? 0
        let maxY = right.map(\.y).max() ?? 0
        let bin: CGFloat = 3
        var silhouette: [CGFloat] = []
        var y = minY
        while y <= maxY {
            let band = right.filter { abs($0.y - y) <= bin * 0.5 }
            if let edge = band.map(\.x).max() {
                silhouette.append(edge)
            }
            y += bin
        }
        guard silhouette.count >= 5, let peak = silhouette.indices.max(by: { silhouette[$0] < silhouette[$1] }) else {
            return 0
        }
        var worst: CGFloat = 0
        var low = silhouette[peak]
        if peak + 1 < silhouette.count {
            for index in (peak + 1)..<silhouette.count {
                low = min(low, silhouette[index])
                worst = max(worst, silhouette[index] - low)
            }
        }
        low = silhouette[peak]
        if peak > 0 {
            for index in stride(from: peak - 1, through: 0, by: -1) {
                low = min(low, silhouette[index])
                worst = max(worst, silhouette[index] - low)
            }
        }
        return worst
    }

    /// A kink with straight neighbors is a polygon vertex. A smooth curve is not.
    private func isolatedFacets(_ turns: [CGFloat]) -> Int {
        guard turns.count >= 5 else { return 0 }
        var count = 0
        for index in 0..<turns.count {
            let previous = turns[(index + turns.count - 2) % turns.count]
            let next = turns[(index + 2) % turns.count]
            if turns[index] > 0.5, previous < 0.12, next < 0.12 {
                count += 1
            }
        }
        return count
    }

    /// Largest direction change along the paper edge, in radians.
    private func turningSamples(_ path: SwiftUI.Path, spacing: CGFloat) -> [CGFloat] {
        let points = resampled(path.cgPath, spacing: spacing)
        guard points.count >= 3 else { return [] }
        return (0..<points.count).map { index in
            let previous = points[(index + points.count - 1) % points.count]
            let next = points[(index + 1) % points.count]
            let point = points[index]
            let ux = point.x - previous.x
            let uy = point.y - previous.y
            let vx = next.x - point.x
            let vy = next.y - point.y
            return abs(atan2(ux * vy - uy * vx, ux * vx + uy * vy))
        }
    }

    private func resampled(_ path: CGPath, spacing: CGFloat) -> [CGPoint] {
        var raw: [CGPoint] = []
        path.applyWithBlock { element in
            let values = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                raw.append(values[0])
            case .addLineToPoint:
                raw.append(values[0])
            case .addQuadCurveToPoint:
                appendCurve(&raw, from: raw.last ?? values[1], controls: [values[0]], to: values[1])
            case .addCurveToPoint:
                appendCurve(&raw, from: raw.last ?? values[2], controls: [values[0], values[1]], to: values[2])
            default:
                break
            }
        }
        guard raw.count >= 2 else { return raw }
        var spaced: [CGPoint] = [raw[0]]
        var carry: CGFloat = 0
        for index in 1..<raw.count {
            var cursor = raw[index - 1]
            let end = raw[index]
            var span = hypot(end.x - cursor.x, end.y - cursor.y)
            var remaining = spacing - carry
            while span + 0.001 >= remaining, span > 0.001 {
                let step = remaining / span
                cursor = CGPoint(x: cursor.x + (end.x - cursor.x) * step, y: cursor.y + (end.y - cursor.y) * step)
                spaced.append(cursor)
                span = hypot(end.x - cursor.x, end.y - cursor.y)
                remaining = spacing
                carry = 0
            }
            carry += span
        }
        return spaced
    }

    private func appendCurve(_ points: inout [CGPoint], from start: CGPoint, controls: [CGPoint], to end: CGPoint) {
        let steps = 8
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            if controls.count == 1 {
                let u = 1 - t
                points.append(CGPoint(
                    x: u * u * start.x + 2 * u * t * controls[0].x + t * t * end.x,
                    y: u * u * start.y + 2 * u * t * controls[0].y + t * t * end.y
                ))
            } else if controls.count == 2 {
                let u = 1 - t
                points.append(CGPoint(
                    x: u * u * u * start.x + 3 * u * u * t * controls[0].x + 3 * u * t * t * controls[1].x + t * t * t * end.x,
                    y: u * u * u * start.y + 3 * u * u * t * controls[0].y + 3 * u * t * t * controls[1].y + t * t * t * end.y
                ))
            }
        }
    }

    private func samples(_ path: SwiftUI.Path) -> [CGPoint] {
        var points: [CGPoint] = []
        path.cgPath.applyWithBlock { element in
            let values = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                points.append(values[0])
            case .addQuadCurveToPoint:
                points.append(values[1])
            case .addCurveToPoint:
                points.append(values[2])
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
        return points
    }

    func testGroupImageIsOneMaskAndDoesNotCastTheShadow() throws {
        let weave = try weaveImage()
        let backing = StickerBacking(
            width: 12,
            smoothness: 1,
            image: StickerImage(image: weave, placement: .fill, opacity: 1),
            shadow: StickerShadow(opacity: 0.5, x: 10, y: 8, radius: 4, color: UIColor.black)
        )
        let size = CGSize(width: 260, height: 180)
        let lines = SketchGroupRenderer.silhouetteLines(
            parts: [
                SketchPart(solid(Rectangle(x: 24, y: 30, width: 90, height: 70), .systemBlue)),
                SketchPart(solid(Rectangle(x: 80, y: 48, width: 80, height: 60), .systemRed))
            ],
            backing: backing,
            size: size
        )
        let sheet = StickerBackingBuilder.commands(for: lines, outward: backing.width, backing: backing, seed: 4)
        let images = sheet.filter { $0.stickerImage != nil }
        XCTAssertGreaterThan(images.count, 0)
        XCTAssertLessThanOrEqual(images.count, 2)
        XCTAssertTrue(images.allSatisfy { $0.sheetShadow == nil })
        XCTAssertEqual(images[0].fillRule, .evenOdd)
        let shadowed = sheet.filter { $0.sheetShadow != nil }
        XCTAssertFalse(shadowed.isEmpty)
        XCTAssertTrue(shadowed.allSatisfy { $0.stickerImage == nil })
        XCTAssertEqual(lines.filter { abs(signedArea($0.points)) > 80 }.count, 1)
    }

    private func solid(_ shape: Drawable, _ color: UIColor) -> RoughView {
        var view = RoughView().roughness(0).bowing(0).strokeWidth(2).fillStyle(.solid).seed(4)
        view.options.stroke = color
        view.options.fill = color
        return view.draw(shape)
    }

    private func signedArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            sum += points[index].x * next.y - next.x * points[index].y
        }
        return sum * 0.5
    }

    /// Synthetic 16×16 checker committed at `Fixtures/sticker-weave.png`.
    /// Rose `(214, 64, 92)` and teal `(40, 120, 150)` in 4-point blocks.
    /// Drawn for these tests. It is not a photograph or a third-party asset.
    private func weaveData() throws -> Data {
        try XCTUnwrap(StickerWeaveFixture.data(), "sticker-weave.png is missing from the test bundle")
    }

    private func weaveImage() throws -> UIImage {
        try XCTUnwrap(StickerWeaveFixture.image())
    }

    private func solidImage(_ color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private struct RGBA {
        var red: Int
        var green: Int
        var blue: Int
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> RGBA {
        let width = image.width
        let height = image.height
        XCTAssertGreaterThan(width, x)
        XCTAssertGreaterThan(height, y)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(drew)
        let flippedY = height - 1 - y
        let offset = flippedY * width * 4 + x * 4
        return RGBA(
            red: Int(pixels[offset]),
            green: Int(pixels[offset + 1]),
            blue: Int(pixels[offset + 2])
        )
    }
}
