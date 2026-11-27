import CoreText
import UIKit
import XCTest
@testable import Sketchy

/// Solid fills of letters with counters and with overlapping same-winding contours.
///
/// Even-odd keeps a counter empty and also cancels a region covered by two
/// contours that wind the same way. Fredoka builds `b`, `d`, `g`, `p`, and `q`
/// that way. San Francisco's `d` and `g` are one outline plus a counter, so
/// they already fill. Its `a` and `e` are a single contour that crosses itself;
/// that notch is left alone so those paths stay byte-for-byte.
@MainActor
final class GlyphContourResolverTests: XCTestCase {
    private let phrase = "Good Enough!"
    private let checkedLetters = ["o", "e", "a", "h", "b", "p", "q", "d", "g"]

    func testOverlappingSquaresFillTheIntersection() {
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: 10, height: 10))
        path.addRect(CGRect(x: 6, y: 6, width: 10, height: 10))
        let resolved = GlyphContourResolver.resolve(path)
        XCTAssertTrue(resolved.contains(CGPoint(x: 8, y: 8), using: .evenOdd))
        XCTAssertTrue(resolved.contains(CGPoint(x: 2, y: 2), using: .evenOdd))
        XCTAssertTrue(resolved.contains(CGPoint(x: 12, y: 12), using: .evenOdd))
        XCTAssertFalse(resolved.contains(CGPoint(x: 12, y: 2), using: .evenOdd))
        XCTAssertFalse(path.contains(CGPoint(x: 8, y: 8), using: .evenOdd))
    }

    func testOppositeWindingHoleStaysEmptyWhenTheStemOverlaps() {
        let path = CGMutablePath()
        addCircle(path, center: CGPoint(x: 15, y: 15), radius: 15, clockwise: false)
        addCircle(path, center: CGPoint(x: 15, y: 15), radius: 6, clockwise: true)
        addRect(path, CGRect(x: 22, y: 0, width: 8, height: 30), clockwise: false)
        let overlap = CGPoint(x: 24, y: 15)
        XCTAssertFalse(path.contains(overlap, using: .evenOdd))
        XCTAssertTrue(path.contains(overlap, using: .winding))

        let resolved = GlyphContourResolver.resolve(path)
        XCTAssertTrue(resolved.contains(overlap, using: .evenOdd), "the stem overlap should fill")
        XCTAssertTrue(resolved.contains(CGPoint(x: 6, y: 15), using: .evenOdd), "the bowl should stay filled")
        XCTAssertFalse(resolved.contains(CGPoint(x: 15, y: 15), using: .evenOdd), "the counter should stay open")
        XCTAssertFalse(resolved.contains(CGPoint(x: 40, y: 15), using: .evenOdd))
    }

    func testDisjointContoursStayUntouched() {
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: 4, height: 10))
        path.addRect(CGRect(x: 8, y: 0, width: 4, height: 4))
        XCTAssertEqual(describe(path), describe(GlyphContourResolver.resolve(path)))
    }

    func testResolveIsIdempotent() {
        let path = CGMutablePath()
        addCircle(path, center: CGPoint(x: 15, y: 15), radius: 15, clockwise: false)
        addCircle(path, center: CGPoint(x: 15, y: 15), radius: 6, clockwise: true)
        addRect(path, CGRect(x: 22, y: 0, width: 8, height: 30), clockwise: false)
        let once = GlyphContourResolver.resolve(path)
        let twice = GlyphContourResolver.resolve(once)
        XCTAssertEqual(describe(once), describe(twice))
    }

    func testSystemGoodEnoughPathIsUnchanged() {
        let font = UIFont.systemFont(ofSize: 40, weight: .semibold)
        let raw = rawPath(phrase, font: font)
        let converted = TextPathConverter.path(from: phrase, font: font)
        XCTAssertEqual(raw.toSVGPathString(), converted.toSVGPathString())
    }

    func testHelveticaNoteIsUnchanged() {
        let font = UIFont(name: "Helvetica-Bold", size: 48) ?? UIFont.boldSystemFont(ofSize: 48)
        let raw = rawPath("Note", font: font)
        let converted = TextPathConverter.path(from: "Note", font: font)
        XCTAssertEqual(raw.toSVGPathString(), converted.toSVGPathString())
    }

    func testSystemLettersKeepCountersAndDoNotRewriteSingleContours() {
        let font = UIFont.systemFont(ofSize: 40, weight: .semibold)
        for letter in checkedLetters {
            assertLetter(letter, font: font, requireOverlap: false)
        }
    }

    func testFredokaOverlappingLettersFillAndKeepCounters() throws {
        let font = try XCTUnwrap(FredokaFixture.font(size: 40))
        for letter in ["b", "d", "g", "p", "q"] {
            assertLetter(letter, font: font, requireOverlap: true)
        }
        for letter in ["o", "e", "a", "h"] {
            assertLetter(letter, font: font, requireOverlap: false)
            let raw = rawPath(letter, font: font)
            let converted = TextPathConverter.path(from: letter, font: font)
            XCTAssertEqual(raw.toSVGPathString(), converted.toSVGPathString(), "\(letter) should be unchanged")
        }
    }

    func testFredokaGoodEnoughKeepsBodyAndCounters() throws {
        let font = try XCTUnwrap(FredokaFixture.font(size: 40))
        let raw = rawPath(phrase, font: font)
        let roundTrip = UIBezierPath(svgPath: TextPathConverter.path(from: phrase, font: font).toSVGPathString()).cgPath
        // The crescent is a few points wide inside a long word, so a grid can miss it.
        // Per-letter tests require the overlap. Here, every sample the grid does hit
        // must fill, and counters in the word must stay empty.
        let samples = sample(raw, steps: 48)
        for point in samples.body {
            XCTAssertTrue(roundTrip.contains(point, using: .evenOdd))
        }
        for point in samples.overlap {
            XCTAssertTrue(roundTrip.contains(point, using: .evenOdd))
        }
        for point in samples.counters {
            XCTAssertFalse(roundTrip.contains(point, using: .evenOdd))
        }
    }

    // MARK: - Letters

    private func assertLetter(
        _ letter: String,
        font: UIFont,
        requireOverlap: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let raw = rawPath(letter, font: font)
        let converted = TextPathConverter.path(from: letter, font: font)
        let roundTrip = UIBezierPath(svgPath: converted.toSVGPathString()).cgPath
        let samples = sample(raw)
        if requireOverlap {
            XCTAssertFalse(samples.overlap.isEmpty, "\(letter) should overlap", file: file, line: line)
        }
        if samples.overlap.isEmpty || !hasSameWindingOverlap(raw) {
            XCTAssertEqual(
                raw.toSVGPathString(),
                converted.toSVGPathString(),
                "\(letter) path changed",
                file: file,
                line: line
            )
        }
        for point in samples.body {
            XCTAssertTrue(roundTrip.contains(point, using: .evenOdd), "\(letter) body", file: file, line: line)
        }
        for point in samples.overlap where hasSameWindingOverlap(raw) {
            XCTAssertTrue(roundTrip.contains(point, using: .evenOdd), "\(letter) overlap", file: file, line: line)
        }
        for point in samples.counters {
            XCTAssertFalse(roundTrip.contains(point, using: .evenOdd), "\(letter) counter", file: file, line: line)
        }
    }

    /// True when two contours share the dominant winding and cover a common area.
    private func hasSameWindingOverlap(_ path: CGPath) -> Bool {
        let contours = contours(of: path)
        guard let dominant = contours.max(by: { abs($0.area) < abs($1.area) }) else { return false }
        let solidIsPositive = dominant.area >= 0
        let solids = contours.filter { ($0.area >= 0) == solidIsPositive && abs($0.area) > 0.25 }
        guard solids.count >= 2 else { return false }
        return !sample(path).overlap.isEmpty
    }

    // MARK: - Sampling

    private struct Samples {
        var body: [CGPoint]
        var overlap: [CGPoint]
        var counters: [CGPoint]
    }

    /// Interior points of the raw glyph, inset so a boundary sample does not count.
    private func sample(_ path: CGPath, steps: Int = 22) -> Samples {
        let box = path.boundingBoxOfPath
        guard box.width > 1, box.height > 1 else { return Samples(body: [], overlap: [], counters: []) }
        var body: [CGPoint] = []
        var overlap: [CGPoint] = []
        var counters: [CGPoint] = []
        for row in 0..<steps {
            for column in 0..<steps {
                let point = CGPoint(
                    x: box.minX + (CGFloat(column) + 0.5) / CGFloat(steps) * box.width,
                    y: box.minY + (CGFloat(row) + 0.5) / CGFloat(steps) * box.height
                )
                let even = path.contains(point, using: .evenOdd)
                let wind = path.contains(point, using: .winding)
                guard inset(point, path: path, even: even, wind: wind) else { continue }
                if even && wind {
                    body.append(point)
                } else if wind && !even {
                    overlap.append(point)
                } else if !even && !wind {
                    counters.append(point)
                }
            }
        }
        return Samples(body: body, overlap: overlap, counters: counters)
    }

    /// The point and its four neighbors agree, so this is not the edge of a contour.
    private func inset(_ point: CGPoint, path: CGPath, even: Bool, wind: Bool) -> Bool {
        let shift: CGFloat = 0.45
        for neighbor in [
            CGPoint(x: point.x + shift, y: point.y),
            CGPoint(x: point.x - shift, y: point.y),
            CGPoint(x: point.x, y: point.y + shift),
            CGPoint(x: point.x, y: point.y - shift)
        ] {
            if path.contains(neighbor, using: .evenOdd) != even { return false }
            if path.contains(neighbor, using: .winding) != wind { return false }
        }
        // Counters are the empty interior. Drop the margin around the glyph.
        if !even && !wind {
            let box = path.boundingBoxOfPath.insetBy(dx: boxInset(path), dy: boxInset(path))
            if !box.contains(point) { return false }
        }
        return true
    }

    private func boxInset(_ path: CGPath) -> CGFloat {
        let box = path.boundingBoxOfPath
        return min(box.width, box.height) * 0.18
    }

    // MARK: - Paths

    /// Glyph outlines before the overlap union, in the same positions `TextPathConverter` uses.
    private func rawPath(_ string: String, font: UIFont) -> CGPath {
        let attributed = NSAttributedString(string: string, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        let mutable = CGMutablePath()
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let fontObject = attributes[kCTFontAttributeName as NSAttributedString.Key] else { continue }
            let fontRef = fontObject as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRangeMake(0, count), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, count), &positions)
            for index in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(fontRef, glyphs[index], nil) else { continue }
                mutable.addPath(
                    glyph,
                    transform: CGAffineTransform(translationX: positions[index].x, y: positions[index].y)
                )
            }
        }
        return mutable
    }

    private struct Ring {
        var area: CGFloat
    }

    private func contours(of path: CGPath) -> [Ring] {
        var rings: [Ring] = []
        var ring: [CGPoint] = []
        var last = CGPoint.zero
        func close() {
            guard ring.count >= 3 else {
                ring = []
                return
            }
            var sum: CGFloat = 0
            for index in ring.indices {
                let next = ring[(index + 1) % ring.count]
                sum += ring[index].x * next.y - next.x * ring[index].y
            }
            rings.append(Ring(area: sum / 2))
            ring = []
        }
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                if !ring.isEmpty { close() }
                last = points[0]
                ring = [last]
            case .addLineToPoint:
                ring.append(points[0])
                last = points[0]
            case .addQuadCurveToPoint:
                ring.append(points[1])
                last = points[1]
            case .addCurveToPoint:
                ring.append(points[2])
                last = points[2]
            case .closeSubpath:
                close()
            @unknown default:
                break
            }
        }
        if !ring.isEmpty { close() }
        return rings
    }

    private func addRect(_ path: CGMutablePath, _ rect: CGRect, clockwise: Bool) {
        let minX = rect.minX
        let minY = rect.minY
        let maxX = rect.maxX
        let maxY = rect.maxY
        path.move(to: CGPoint(x: minX, y: minY))
        if clockwise {
            path.addLine(to: CGPoint(x: minX, y: maxY))
            path.addLine(to: CGPoint(x: maxX, y: maxY))
            path.addLine(to: CGPoint(x: maxX, y: minY))
        } else {
            path.addLine(to: CGPoint(x: maxX, y: minY))
            path.addLine(to: CGPoint(x: maxX, y: maxY))
            path.addLine(to: CGPoint(x: minX, y: maxY))
        }
        path.closeSubpath()
    }

    private func addCircle(
        _ path: CGMutablePath,
        center: CGPoint,
        radius: CGFloat,
        clockwise: Bool
    ) {
        path.move(to: CGPoint(x: center.x + radius, y: center.y))
        let steps = 48
        for step in 1...steps {
            let turns = CGFloat(step) / CGFloat(steps) * 2 * .pi
            let angle = clockwise ? -turns : turns
            path.addLine(to: CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            ))
        }
        path.closeSubpath()
    }

    private func describe(_ path: CGPath) -> String {
        var text = ""
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                text += String(format: "M%.3f,%.3f", points[0].x, points[0].y)
            case .addLineToPoint:
                text += String(format: "L%.3f,%.3f", points[0].x, points[0].y)
            case .addQuadCurveToPoint:
                text += String(format: "Q%.3f,%.3f", points[1].x, points[1].y)
            case .addCurveToPoint:
                text += String(format: "C%.3f,%.3f", points[2].x, points[2].y)
            case .closeSubpath:
                text += "Z"
            @unknown default:
                break
            }
        }
        return text
    }
}
