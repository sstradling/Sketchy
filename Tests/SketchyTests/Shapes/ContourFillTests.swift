import CoreGraphics
import UIKit
import XCTest
@testable import Sketchy

/// Contour strokes, graduation, falloff, holes, and the wrapping drift field.
@MainActor
final class ContourFillTests: XCTestCase {
    func testFieldSlidesByOneSlotAndWraps() {
        let start = ContourField.placements(count: 8, falloff: 0, phaseSlots: 0)
        let shifted = ContourField.placements(count: 8, falloff: 0, phaseSlots: 1)
        let wrapped = ContourField.placements(count: 8, falloff: 0, phaseSlots: 8)
        let backward = ContourField.placements(count: 8, falloff: 0, phaseSlots: -1)
        for index in 0..<8 {
            XCTAssertEqual(shifted[index].u, start[(index + 1) % 8].u, accuracy: 1e-5)
            XCTAssertEqual(wrapped[index].u, start[index].u, accuracy: 1e-5)
            XCTAssertEqual(backward[index].u, start[(index + 7) % 8].u, accuracy: 1e-5)
        }
    }

    func testFalloffPacksSlotsTowardTheGuide() {
        let placed = ContourField.placements(count: 10, falloff: 1, phaseSlots: 0)
            .map(\.u)
            .sorted()
        let nearGuide = placed[1] - placed[0]
        let farSide = placed[9] - placed[8]
        XCTAssertLessThan(nearGuide, farSide)
        XCTAssertEqual(ContourGeometry.widthScale(u: 0, falloff: 1), 0.22, accuracy: 0.001)
        XCTAssertEqual(ContourGeometry.widthScale(u: 1, falloff: 1), 1, accuracy: 0.001)
        XCTAssertEqual(ContourGeometry.widthScale(u: 0.4, falloff: 0), 1, accuracy: 0.001)
    }

    func testIntensityZeroIsStraight() {
        let plan = ContourGeometry.plan(polygon: dome, options: guideOptions(intensity: 0))
        XCTAssertGreaterThan(plan.strokes.count, 3)
        for stroke in plan.strokes where chord(stroke.points) > 20 {
            XCTAssertLessThan(sagitta(stroke.points), 0.05, "slot \(stroke.slot)")
        }
    }

    func testGraduationFlattensTheInnerStrokes() {
        let full = ContourGeometry.plan(polygon: dome, options: guideOptions(intensity: 1))
        var eased = guideOptions(intensity: 1)
        eased.contourIntensityStart = 1
        eased.contourIntensityEnd = 0.25
        eased.contourGradientAngle = 90
        eased.contourEasing = .linear
        let flat = ContourGeometry.plan(polygon: dome, options: eased)

        let fullBottom = try! XCTUnwrap(full.strokes.max(by: { meanY($0) < meanY($1) }))
        let flatBottom = try! XCTUnwrap(flat.strokes.max(by: { meanY($0) < meanY($1) }))
        let fullTop = try! XCTUnwrap(full.strokes.min(by: { meanY($0) < meanY($1) }))
        let flatTop = try! XCTUnwrap(flat.strokes.min(by: { meanY($0) < meanY($1) }))

        // Intensity 1 follows the horizon's wide bow. The bottom stroke still
        // crosses the dome. It does not shrink into a ring around the center.
        XCTAssertGreaterThan(chord(fullBottom.points), 160)
        XCTAssertGreaterThan(chord(flatBottom.points), 160)
        XCTAssertLessThan(sagitta(fullBottom.points), sagitta(fullTop.points) * 1.4)
        XCTAssertLessThan(sagitta(flatBottom.points), sagitta(flatTop.points) * 0.55)
        XCTAssertGreaterThan(sagitta(flatTop.points), 4)
    }

    func testIntensityChangesAlongAStroke() {
        let wide: [[Float]] = [[0, 40], [400, 40], [400, 220], [0, 220]]
        var options = guideOptions(intensity: 1)
        options.contourGuide = .arc(center: ContourPoint(x: 200, y: 760), radius: 620)
        options.contourIntensityStart = 0
        options.contourIntensityEnd = 2
        options.contourGradientAngle = 0
        let plan = ContourGeometry.plan(polygon: wide, options: options)
        let stroke = try! XCTUnwrap(plan.strokes.max(by: { chord($0.points) < chord($1.points) }))
        let left = stroke.points.filter { $0.x > 30 && $0.x < 120 }
        let right = stroke.points.filter { $0.x > 280 && $0.x < 370 }
        XCTAssertGreaterThan(left.count, 1)
        XCTAssertGreaterThan(right.count, 1)
        let leftBow = meanDeviation(left, from: stroke.points)
        let rightBow = meanDeviation(right, from: stroke.points)
        XCTAssertGreaterThan(rightBow, leftBow * 2.5)

        let ordered = plan.strokes.sorted { meanY($0) < meanY($1) }
        for index in 1..<ordered.count {
            for x in [Float(80), 200, 320] {
                let above = y(at: x, on: ordered[index - 1].points)
                let below = y(at: x, on: ordered[index].points)
                if let above, let below {
                    XCTAssertLessThan(above, below + 0.5, "strokes crossed at x=\(x)")
                }
            }
        }
    }

    func testEaseCurves() {
        XCTAssertEqual(ContourEasing.linear.value(0.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(ContourEasing.easeInOut.value(0), 0, accuracy: 0.001)
        XCTAssertEqual(ContourEasing.easeInOut.value(1), 1, accuracy: 0.001)
        XCTAssertEqual(ContourEasing.easeInOut.value(0.5), 0.5, accuracy: 0.001)
        XCTAssertLessThan(ContourEasing.easeIn.value(0.5), 0.5)
        XCTAssertGreaterThan(ContourEasing.easeOut.value(0.5), 0.5)
    }

    func testExternalGuideKeepsOneCenter() {
        let center = ContourPoint(x: 300, y: 520)
        let left: [[Float]] = [[20, 80], [130, 80], [130, 170], [20, 170]]
        let lower: [[Float]] = [[180, 220], [280, 230], [270, 300], [170, 290]]
        var options = guideOptions(intensity: 1)
        options.contourGuide = .arc(center: center, radius: 460)
        let first = ContourGeometry.plan(polygon: left, options: options)
        let second = ContourGeometry.plan(polygon: lower, options: options)
        XCTAssertFalse(first.strokes.isEmpty)
        XCTAssertFalse(second.strokes.isEmpty)
        for stroke in first.strokes + second.strokes where chord(stroke.points) > 40 {
            let radius = estimatedRadius(stroke.points)
            XCTAssertEqual(radius, 460, accuracy: 140, "bow should match the shared guide, not a tight local arc")
        }
    }

    func testPolylineGuideFollowsTheNormals() {
        let guide = ContourGuide.polyline(points: [
            ContourPoint(x: 0, y: 20),
            ContourPoint(x: 100, y: 60),
            ContourPoint(x: 200, y: 30)
        ], closed: false)
        let rect: [[Float]] = [[20, 80], [180, 80], [180, 160], [20, 160]]
        var options = guideOptions(intensity: 1)
        options.contourGuide = guide
        let plan = ContourGeometry.plan(polygon: rect, options: options)
        XCTAssertGreaterThan(plan.strokes.count, 2)
        let straight = guideOptions(intensity: 0)
        var flat = straight
        flat.contourGuide = guide
        let flatPlan = ContourGeometry.plan(polygon: rect, options: flat)
        let bowed = plan.strokes.map { sagitta($0.points) }.max() ?? 0
        let flatBow = flatPlan.strokes.map { sagitta($0.points) }.max() ?? 0
        XCTAssertGreaterThan(bowed, 4)
        XCTAssertLessThan(flatBow, 0.05)
    }

    func testEvenOddNotchStaysEmpty() {
        let notch: [[Float]] = [
            [0, 0], [200, 0], [200, 70], [120, 70],
            [120, 130], [200, 130], [200, 200], [0, 200]
        ]
        var options = guideOptions(intensity: 0)
        options.contourGuide = nil
        options.fillAngle = 0
        options.fillSpacing = 4
        let plan = ContourGeometry.plan(polygon: notch, options: options)
        XCTAssertGreaterThan(plan.strokes.count, 4)
        for stroke in plan.strokes {
            for point in stroke.points where point.y > 75 && point.y < 125 {
                XCTAssertLessThanOrEqual(point.x, 122, "stroke entered the notch at \(point)")
            }
        }
    }

    func testSVGHoleUsesEvenOddClip() {
        let path = "M10 10 H110 V90 H10 Z M40 30 H80 V70 H40 Z"
        var options = guideOptions(intensity: 0)
        options.fillStyle = .contour
        options.fill = .black
        options.contourGuide = nil
        options.fillAngle = 0
        options.fillSpacing = 2
        let size = CGSize(width: 140, height: 120)
        let drawing = try! XCTUnwrap(
            NativeGenerator(size: size).generate(drawable: Path(d: path), options: options)
        )
        let clip = SwiftUIRenderer().commands(for: drawing, options: options, in: size)
            .compactMap(\.clipPath)
            .first
        let clipPath = try! XCTUnwrap(clip).cgPath
        let hole = fitted(x: 60, y: 50, pathBounds: CGRect(x: 10, y: 10, width: 100, height: 80), size: size)
        let body = fitted(x: 20, y: 20, pathBounds: CGRect(x: 10, y: 10, width: 100, height: 80), size: size)
        XCTAssertFalse(clipPath.contains(hole, using: .evenOdd, transform: .identity))
        XCTAssertTrue(clipPath.contains(hole, using: .winding, transform: .identity))
        XCTAssertTrue(clipPath.contains(body, using: .evenOdd, transform: .identity))
    }

    func testFalloffScalesWidthAndSpacing() {
        var options = guideOptions(intensity: 1)
        options.contourFalloff = 1
        options.contourGuide = .arc(center: ContourPoint(x: 100, y: 420), radius: 420)
        let plan = ContourGeometry.plan(polygon: dome, options: options)
        let ordered = plan.strokes.sorted { meanY($0) < meanY($1) }
        XCTAssertGreaterThan(ordered.count, 4)
        let topGap = meanY(ordered[1]) - meanY(ordered[0])
        let bottomGap = meanY(ordered[ordered.count - 1]) - meanY(ordered[ordered.count - 2])
        XCTAssertLessThan(topGap, bottomGap * 0.75, "strokes should pack toward the horizon and spread toward the bottom")
        XCTAssertLessThan(ordered[0].scale, ordered[ordered.count - 1].scale - 0.2)

        let sets = ContourFiller().fillPolygonSets(points: dome, options: options)
        let scales = sets.compactMap(\.fillLineScale)
        XCTAssertGreaterThan(scales.count, 1)
        XCTAssertGreaterThan(scales.max() ?? 0, (scales.min() ?? 1) + 0.2)
    }

    func testPhaseWrapsTheDrawingAndKeepsTheOutline() {
        let preview = ContourGeometry.plan(polygon: dome, options: guideOptions(intensity: 1))
        let angle = atan2(preview.travel.y, preview.travel.x) * 180 / .pi
        var still = guideOptions(intensity: 1)
        still.contourDrift = ContourDrift(speed: 30, angle: angle, phase: 0)
        let atZero = ContourGeometry.plan(polygon: dome, options: still)
        var turned = still
        turned.contourDrift?.phase = atZero.period
        let atPeriod = ContourGeometry.plan(polygon: dome, options: turned)
        XCTAssertEqual(atZero.strokes.count, atPeriod.strokes.count)
        for (before, after) in zip(atZero.strokes, atPeriod.strokes) {
            XCTAssertEqual(before.slot, after.slot)
            XCTAssertEqual(before.points.count, after.points.count)
            for (left, right) in zip(before.points, after.points) {
                XCTAssertEqual(left.x, right.x, accuracy: 0.02)
                XCTAssertEqual(left.y, right.y, accuracy: 0.02)
            }
        }

        var moved = still
        moved.contourDrift = ContourDrift(speed: 30, angle: angle, phase: atZero.gap * 0.5)
        let shifted = ContourGeometry.plan(polygon: dome, options: moved)
        XCTAssertNotEqual(
            atZero.strokes.map(\.offset).sorted(),
            shifted.strokes.map(\.offset).sorted(),
            "phaseSlots \(atZero.phaseSlots) -> \(shifted.phaseSlots)"
        )
        XCTAssertEqual(shifted.phaseSlots, 0.5, accuracy: 0.02)

        var rough = still
        rough.roughness = 1.4
        rough.bowing = 1
        rough.maxRandomnessOffset = 2
        rough.seed = 42
        let filler = ContourFiller()
        let first = coordinates(filler.fillPolygon(points: dome, options: rough)?.operations ?? [])
        var again = rough
        again.contourDrift = ContourDrift(speed: 30, angle: angle, phase: atZero.period)
        let second = coordinates(filler.fillPolygon(points: dome, options: again)?.operations ?? [])
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first.count, second.count)
        for (left, right) in zip(first, second) {
            XCTAssertEqual(left, right, accuracy: 0.05)
        }

        let size = CGSize(width: 240, height: 300)
        let generator = NativeGenerator(size: size)
        let drawable = Rectangle(x: 10, y: 10, width: 200, height: 260)
        let rect: [[Float]] = [[10, 10], [210, 10], [210, 270], [10, 270]]
        let rectPeriod = ContourGeometry.plan(polygon: rect, options: rough).period
        again.contourDrift = ContourDrift(speed: 30, angle: angle, phase: rectPeriod)
        let drawingA = try! XCTUnwrap(generator.generate(drawable: drawable, options: rough))
        let drawingB = try! XCTUnwrap(generator.generate(drawable: drawable, options: again))
        let outlineA = drawingA.sets.filter { $0.type == .path }.flatMap { coordinates($0.operations) }
        let outlineB = drawingB.sets.filter { $0.type == .path }.flatMap { coordinates($0.operations) }
        XCTAssertEqual(outlineA, outlineB)
        let fillA = drawingA.sets.filter { $0.type == .fillSketch }.flatMap { coordinates($0.operations) }
        let fillB = drawingB.sets.filter { $0.type == .fillSketch }.flatMap { coordinates($0.operations) }
        XCTAssertEqual(fillA.count, fillB.count)
        for (left, right) in zip(fillA, fillB) {
            XCTAssertEqual(left, right, accuracy: 0.05)
        }
    }

    func testSeedRepeatsAndCacheKeyTracksTheGuide() {
        var options = guideOptions(intensity: 0.8)
        options.roughness = 1.5
        options.seed = 19
        let filler = ContourFiller()
        let first = coordinates(filler.fillPolygon(points: dome, options: options)?.operations ?? [])
        let second = coordinates(filler.fillPolygon(points: dome, options: options)?.operations ?? [])
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second)
        var other = options
        other.seed = 20
        XCTAssertNotEqual(first, coordinates(filler.fillPolygon(points: dome, options: other)?.operations ?? []))

        let drawable = Rectangle(x: 0, y: 0, width: 80, height: 60)
        let size = CGSize(width: 100, height: 80)
        let key = DrawingCacheKey(drawable: drawable, size: size, options: options)
        var intensity = options
        intensity.contourIntensity = 0.1
        var falloff = options
        falloff.contourFalloff = 0.8
        var phase = options
        phase.contourDrift = ContourDrift(speed: 0, angle: 90, phase: 15)
        var guide = options
        guide.contourGuide = .arc(center: ContourPoint(x: 10, y: 10), radius: 40)
        XCTAssertNotEqual(key, DrawingCacheKey(drawable: drawable, size: size, options: intensity))
        XCTAssertNotEqual(key, DrawingCacheKey(drawable: drawable, size: size, options: falloff))
        XCTAssertNotEqual(key, DrawingCacheKey(drawable: drawable, size: size, options: phase))
        XCTAssertNotEqual(key, DrawingCacheKey(drawable: drawable, size: size, options: guide))
        XCTAssertNotEqual(options.cacheHash, intensity.cacheHash)

        let left = Polygon(points: [Point(x: 0, y: 0), Point(x: 40, y: 0), Point(x: 20, y: 30)])
        let right = Polygon(points: [Point(x: 80, y: 10), Point(x: 120, y: 10), Point(x: 100, y: 40)])
        XCTAssertNotEqual(
            DrawingCacheKey(drawable: left, size: size, options: options),
            DrawingCacheKey(drawable: right, size: size, options: options),
            "polygon points belong in the drawing cache key"
        )
    }

    func testModifiersWriteContourOptions() {
        let guide = ContourGuide.arc(center: CGPoint(x: 4, y: 9), radius: 12)
        let view = RoughView()
            .fillStyle(.contour)
            .contourGuide(guide)
            .contourIntensity(from: 0.2, to: 1.4, angle: 10, easing: .easeInOut)
            .contourFalloff(1.5)
            .contourDrift(angle: 90, speed: 12, phase: 3)
        XCTAssertEqual(view.options.fillStyle, .contour)
        XCTAssertEqual(view.options.contourGuide, guide)
        XCTAssertEqual(view.options.contourIntensityStart, 0.2)
        XCTAssertEqual(view.options.contourIntensityEnd, 1.4)
        XCTAssertEqual(view.options.contourGradientAngle, 10)
        XCTAssertEqual(view.options.contourEasing, .easeInOut)
        XCTAssertEqual(view.options.contourFalloff, 1)
        XCTAssertEqual(view.options.contourDrift?.speed, 12)
        XCTAssertEqual(view.options.contourDrift?.phase, 3)
        let cleared = view.contourIntensity(0.5)
        XCTAssertNil(cleared.options.contourIntensityStart)
        XCTAssertEqual(cleared.options.contourIntensity, 0.5)
    }

    private let dome: [[Float]] = [[0, 0], [200, 0], [200, 280], [0, 280]]

    private func guideOptions(intensity: Float) -> Options {
        var options = Options()
        options.fillStyle = .contour
        options.seed = 7
        options.roughness = 0
        options.bowing = 0
        options.maxRandomnessOffset = 0
        options.fillWeight = 2
        options.fillSpacing = 8
        options.contourIntensity = intensity
        options.contourGuide = .arc(center: ContourPoint(x: 100, y: 420), radius: 420)
        return options
    }

    private func sagitta(_ points: [ContourPoint]) -> Float {
        guard let first = points.first, let last = points.last, points.count > 2 else { return 0 }
        let dx = last.x - first.x
        let dy = last.y - first.y
        let length = hypot(dx, dy)
        guard length > 1 else { return 0 }
        return points.reduce(Float(0)) { best, point in
            max(best, abs((point.x - first.x) * dy - (point.y - first.y) * dx) / length)
        }
    }

    private func meanDeviation(_ points: [ContourPoint], from stroke: [ContourPoint]) -> Float {
        guard let first = stroke.first, let last = stroke.last, !points.isEmpty else { return 0 }
        let dx = last.x - first.x
        let dy = last.y - first.y
        let length = max(hypot(dx, dy), 0.001)
        let total = points.reduce(Float(0)) { total, point in
            total + abs((point.x - first.x) * dy - (point.y - first.y) * dx) / length
        }
        return total / Float(points.count)
    }

    private func meanY(_ stroke: ContourStroke) -> Float {
        stroke.points.reduce(Float(0)) { $0 + $1.y } / Float(stroke.points.count)
    }

    private func chord(_ points: [ContourPoint]) -> Float {
        guard let first = points.first, let last = points.last else { return 0 }
        return hypot(last.x - first.x, last.y - first.y)
    }

    private func estimatedRadius(_ points: [ContourPoint]) -> Float {
        let sag = sagitta(points)
        let span = chord(points)
        guard sag > 0.4 else { return .greatestFiniteMagnitude }
        return span * span / (8 * sag)
    }

    private func y(at x: Float, on points: [ContourPoint]) -> Float? {
        guard points.count >= 2 else { return nil }
        for index in 1..<points.count {
            let left = points[index - 1]
            let right = points[index]
            let span = right.x - left.x
            guard abs(span) > 0.001 else { continue }
            let t = (x - left.x) / span
            if t >= 0, t <= 1 {
                return left.y + (right.y - left.y) * t
            }
        }
        return nil
    }

    private func fitted(x: CGFloat, y: CGFloat, pathBounds: CGRect, size: CGSize) -> CGPoint {
        let scale = min(size.width / pathBounds.width, size.height / pathBounds.height)
        let offsetX = (size.width - pathBounds.width * scale) / 2 - pathBounds.minX * scale
        let offsetY = (size.height - pathBounds.height * scale) / 2 - pathBounds.minY * scale
        return CGPoint(x: x * scale + offsetX, y: y * scale + offsetY)
    }

    private func coordinates(_ operations: [Sketchy.Operation]) -> [Float] {
        operations.flatMap { operation -> [Float] in
            switch operation {
            case let move as Move:
                return [move.point.x, move.point.y]
            case let line as LineTo:
                return [line.point.x, line.point.y]
            case let curve as BezierCurveTo:
                return [
                    curve.controlPoint1.x, curve.controlPoint1.y,
                    curve.controlPoint2.x, curve.controlPoint2.y,
                    curve.point.x, curve.point.y
                ]
            default:
                return []
            }
        }
    }
}
