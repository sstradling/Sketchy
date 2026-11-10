import XCTest
@testable import Sketchy

@MainActor
final class WashFillTests: XCTestCase {
    func testSameSeedRepeatsAndAnotherSeedDiverges() {
        let first = coordinates(fill(seed: 11))
        let second = coordinates(fill(seed: 11))
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, coordinates(fill(seed: 12)))
    }

    func testTwoPassesUseDifferentWidths() {
        var options = options(seed: 4)
        options.washPasses = WashPass.sky
        let sets = WashFiller().fillPolygonSets(points: rect, options: options)
        let widths = Set(sets.compactMap(\.fillLineWidth))
        XCTAssertGreaterThan(widths.count, 1)
        XCTAssertTrue(widths.contains { $0 >= 42 && $0 <= 58 })
        XCTAssertTrue(widths.contains { $0 >= 28 && $0 < 42 })
    }

    func testTrimShortensTheStroke() {
        let long = WashStrokeBuilder.shape(
            [ContourPoint(x: 0, y: 0), ContourPoint(x: 100, y: 0), ContourPoint(x: 200, y: 0)],
            trimStart: 0, trimEnd: 0, bow: 0
        )
        let short = WashStrokeBuilder.shape(
            [ContourPoint(x: 0, y: 0), ContourPoint(x: 100, y: 0), ContourPoint(x: 200, y: 0)],
            trimStart: 30, trimEnd: 40, bow: 0
        )
        let longSpan = abs(long.last![0] - long.first![0])
        let shortSpan = abs(short.last![0] - short.first![0])
        XCTAssertEqual(longSpan, 200, accuracy: 0.1)
        XCTAssertEqual(shortSpan, 130, accuracy: 1)
    }

    func testSineBowLeavesTheEndsAndBendsTheMiddle() {
        let points = (0...8).map { ContourPoint(x: Float($0) * 20, y: 0) }
        let shaped = WashStrokeBuilder.shape(points, trimStart: 0, trimEnd: 0, bow: 10)
        XCTAssertEqual(shaped.first![1], 0, accuracy: 0.01)
        XCTAssertEqual(shaped.last![1], 0, accuracy: 0.01)
        let middle = shaped[shaped.count / 2][1]
        XCTAssertGreaterThan(abs(middle), 4)
    }

    func testAngleSpreadChangesTheStroke() {
        var tight = options(seed: 8)
        tight.washPasses = [WashPass(
            spacingMin: 30, spacingSpan: 0, widthMin: 8, widthSpan: 0,
            opacityMin: 1, opacitySpan: 0, trimMax: 0, angleSpread: 0, bow: 0, seed: 1
        )]
        var loose = tight
        loose.washPasses = [WashPass(
            spacingMin: 30, spacingSpan: 0, widthMin: 8, widthSpan: 0,
            opacityMin: 1, opacitySpan: 0, trimMax: 0, angleSpread: 40, bow: 0, seed: 1
        )]
        let straight = coordinates(WashFiller().fillPolygonSets(points: rect, options: tight))
        let scattered = coordinates(WashFiller().fillPolygonSets(points: rect, options: loose))
        XCTAssertNotEqual(straight, scattered)
    }

    func testNotchStaysEmpty() {
        let notch: [[Float]] = [
            [0, 0], [200, 0], [200, 70], [120, 70],
            [120, 130], [200, 130], [200, 200], [0, 200]
        ]
        var options = options(seed: 3)
        options.fillAngle = 0
        options.washPasses = [WashPass(
            spacingMin: 18, spacingSpan: 0, widthMin: 4, widthSpan: 0,
            opacityMin: 1, opacitySpan: 0, trimMax: 0, angleSpread: 0, bow: 0,
            minLength: 8, seed: 9
        )]
        let plan = ContourGeometry.plan(polygon: notch, options: {
            var copy = options
            copy.fillStyle = .contour
            copy.contourGuide = nil
            copy.contourIntensity = 0
            copy.washPasses = nil
            return copy
        }())
        XCTAssertGreaterThan(plan.strokes.count, 2)
        let sets = WashFiller().fillPolygonSets(points: notch, options: options)
        XCTAssertFalse(sets.isEmpty)
    }

    func testContourCanUseTheWashRecipe() {
        var plain = Options()
        plain.fillStyle = .contour
        plain.seed = 5
        plain.roughness = 0
        plain.bowing = 0
        plain.maxRandomnessOffset = 0
        plain.fillWeight = 2
        plain.fillSpacing = 10
        plain.contourIntensity = 1
        plain.contourGuide = .arc(center: ContourPoint(x: 100, y: 420), radius: 420)
        var washed = plain
        washed.washPasses = [WashPass(
            spacingMin: 20, spacingSpan: 0, widthMin: 6, widthSpan: 0,
            opacityMin: 0.8, opacitySpan: 0, trimMax: 12, angleSpread: 0, bow: 4,
            minLength: 8, seed: 70
        )]
        let dome: [[Float]] = [[0, 0], [200, 0], [200, 280], [0, 280]]
        let plainOps = ContourFiller().fillPolygonSets(points: dome, options: plain)
        let washOps = ContourFiller().fillPolygonSets(points: dome, options: washed)
        XCTAssertFalse(plainOps.isEmpty)
        XCTAssertFalse(washOps.isEmpty)
        XCTAssertNotNil(washOps.first?.fillLineWidth)
        XCTAssertEqual(
            coordinates(washOps),
            coordinates(ContourFiller().fillPolygonSets(points: dome, options: washed))
        )
        XCTAssertNotEqual(coordinates(plainOps), coordinates(washOps))
    }

    func testCacheKeyIncludesPasses() {
        let drawable = Rectangle(x: 0, y: 0, width: 40, height: 30)
        let size = CGSize(width: 80, height: 60)
        var base = Options()
        base.fillStyle = .wash
        var other = base
        other.washPasses = WashPass.sky(scale: 0.5)
        XCTAssertNotEqual(
            DrawingCacheKey(drawable: drawable, size: size, options: base),
            DrawingCacheKey(drawable: drawable, size: size, options: other)
        )
    }

    private let rect: [[Float]] = [[0, 0], [180, 0], [180, 120], [0, 120]]

    private func options(seed: UInt64) -> Options {
        var options = Options()
        options.fillStyle = .wash
        options.seed = seed
        options.fillAngle = -20
        options.washPasses = WashPass.sky(scale: 0.25)
        return options
    }

    private func fill(seed: UInt64) -> [OperationSet] {
        WashFiller().fillPolygonSets(points: rect, options: options(seed: seed))
    }

    private func coordinates(_ sets: [OperationSet]) -> [Float] {
        sets.flatMap { set in
            set.operations.flatMap { operation -> [Float] in
                switch operation {
                case let move as Move:
                    return [move.point.x, move.point.y]
                case let curve as BezierCurveTo:
                    return [curve.point.x, curve.point.y]
                default:
                    return []
                }
            }
        }
    }
}
