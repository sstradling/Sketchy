//
//  GlyphContourResolver.swift
//  Sketchy
//
//  Copyright ©️2026 Seth Stradling. All Rights Reserved.
//
//  Unions glyph contours that overlap with the same winding. Solid fills use
//  even-odd, which keeps a counter open and also punches out that overlap.
//  Letters built as a bowl plus a stem (`b`, `d`, `g`, `p`, `q` in Fredoka)
//  otherwise draw with a gap between the pieces. A glyph whose contours do
//  not overlap is returned unchanged, so every other outline stays put.
//

import CoreGraphics

/// Repairs a glyph outline so an even-odd fill matches the nonzero winding.
enum GlyphContourResolver {
    /// Flatness of a rebuilt outline, in points. Untouched glyphs keep their curves.
    static let flatness: CGFloat = 0.08

    /// How close two vertices must be before they are the same point.
    private static let mergeDistance: CGFloat = 0.004

    /// How far off an edge the inside/outside probe sits, before it is shortened to the edge.
    private static let probe: CGFloat = 0.06

    /// Returns `path` when its solid contours do not overlap.
    ///
    /// Solid contours share the winding of the largest ring. A ring with the
    /// other winding is a counter and is kept. Overlapping solids are replaced
    /// by their union. The union outline is flattened; counters keep their curves.
    static func resolve(_ path: CGPath) -> CGPath {
        let contours = extract(path)
        guard let dominant = contours.max(by: { abs($0.area) < abs($1.area) }) else { return path }
        let solidIsPositive = dominant.area >= 0
        let solids = contours.filter { ($0.area >= 0) == solidIsPositive && abs($0.area) > 0.25 }
        let holes = contours.filter { ($0.area >= 0) != solidIsPositive && abs($0.area) > 0.25 }
        guard solids.count >= 2, solidsOverlap(solids) else { return path }
        guard let rings = unionRings(solids.map(\.ring)), plausible(rings, solids: solids) else { return path }

        let resolved = CGMutablePath()
        for ring in rings where ring.count >= 3 {
            resolved.move(to: ring[0])
            for point in ring.dropFirst() {
                resolved.addLine(to: point)
            }
            resolved.closeSubpath()
        }
        for hole in holes {
            guard let sample = interiorSample(hole.ring), insideAny(sample, rings) else { continue }
            // Union rings are counterclockwise. A counter has to wind the other way
            // so a nonzero fill stays empty there as well.
            let oriented = hole.area >= 0 ? reversed(hole.curves) : hole.curves
            resolved.addPath(oriented)
        }
        return resolved
    }

    /// One closed subpath: the original curves, a flattened ring, and its signed area.
    private struct Contour {
        var curves: CGPath
        var ring: [CGPoint]
        var area: CGFloat
    }

    /// Splits `path` into closed contours. An unclosed subpath is closed.
    private static func extract(_ path: CGPath) -> [Contour] {
        var contours: [Contour] = []
        var curves = CGMutablePath()
        var ring: [CGPoint] = []
        var last = CGPoint.zero
        var open = false

        func finish() {
            guard open else { return }
            curves.closeSubpath()
            if ring.count >= 2,
               hypot(ring[0].x - ring[ring.count - 1].x, ring[0].y - ring[ring.count - 1].y) < mergeDistance {
                ring.removeLast()
            }
            if ring.count >= 3 {
                contours.append(Contour(curves: curves, ring: ring, area: signedArea(ring)))
            }
            curves = CGMutablePath()
            ring = []
            open = false
        }

        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                finish()
                last = points[0]
                curves.move(to: last)
                ring = [last]
                open = true
            case .addLineToPoint:
                curves.addLine(to: points[0])
                appendLine(to: points[0], into: &ring)
                last = points[0]
            case .addQuadCurveToPoint:
                curves.addQuadCurve(to: points[1], control: points[0])
                flattenQuad(from: last, control: points[0], to: points[1], into: &ring)
                last = points[1]
            case .addCurveToPoint:
                curves.addCurve(to: points[2], control1: points[0], control2: points[1])
                flattenCubic(from: last, control1: points[0], control2: points[1], to: points[2], into: &ring)
                last = points[2]
            case .closeSubpath:
                finish()
            @unknown default:
                break
            }
        }
        finish()
        return contours
    }

    /// True when two solid rings cross or one sits inside the other.
    private static func solidsOverlap(_ solids: [Contour]) -> Bool {
        for index in solids.indices {
            for other in solids.indices where other > index {
                if overlaps(solids[index].ring, solids[other].ring) { return true }
            }
        }
        return false
    }

    /// True when the rings share area. A shared vertex alone does not count.
    private static func overlaps(_ left: [CGPoint], _ right: [CGPoint]) -> Bool {
        guard bounds(left).insetBy(dx: -0.2, dy: -0.2).intersects(bounds(right)) else { return false }
        if edgesCross(left, right) { return true }
        if left.contains(where: { ringContains($0, right) && !onRing($0, right) }) { return true }
        if right.contains(where: { ringContains($0, left) && !onRing($0, left) }) { return true }
        return false
    }

    /// True when a segment of `left` crosses a segment of `right` away from a shared vertex.
    private static func edgesCross(_ left: [CGPoint], _ right: [CGPoint]) -> Bool {
        guard left.count >= 2, right.count >= 2 else { return false }
        for leftIndex in left.indices {
            let start = left[leftIndex]
            let end = left[(leftIndex + 1) % left.count]
            for rightIndex in right.indices {
                if segmentHit(start, end, right[rightIndex], right[(rightIndex + 1) % right.count]) != nil {
                    return true
                }
            }
        }
        return false
    }

    /// Boundary of the union of counterclockwise-or-otherwise rings.
    ///
    /// `nil` when the boundary does not close. The caller keeps the original glyph.
    private static func unionRings(_ polygons: [[CGPoint]]) -> [[CGPoint]]? {
        let oriented = polygons.map { ring -> [CGPoint] in
            let cleanedRing = cleaned(ring)
            return signedArea(cleanedRing) < 0 ? Array(cleanedRing.reversed()) : cleanedRing
        }
        guard oriented.allSatisfy({ $0.count >= 3 }) else { return nil }

        struct Segment {
            var start: CGPoint
            var end: CGPoint
            var polygon: Int
        }
        var segments: [Segment] = []
        for (index, ring) in oriented.enumerated() {
            for pointIndex in ring.indices {
                let start = ring[pointIndex]
                let end = ring[(pointIndex + 1) % ring.count]
                if hypot(start.x - end.x, start.y - end.y) < mergeDistance { continue }
                segments.append(Segment(start: start, end: end, polygon: index))
            }
        }

        struct Hit {
            var t: CGFloat
            var point: CGPoint
        }
        var hits = Array(repeating: [Hit](), count: segments.count)
        for index in segments.indices {
            for other in (index + 1)..<segments.count where segments[index].polygon != segments[other].polygon {
                guard let hit = segmentHit(
                    segments[index].start, segments[index].end,
                    segments[other].start, segments[other].end
                ) else { continue }
                hits[index].append(Hit(t: hit.t, point: hit.point))
                hits[other].append(Hit(t: hit.u, point: hit.point))
            }
        }

        var vertices: [CGPoint] = []
        func vertex(_ point: CGPoint) -> Int {
            for (index, existing) in vertices.enumerated() where hypot(existing.x - point.x, existing.y - point.y) <= mergeDistance {
                return index
            }
            vertices.append(point)
            return vertices.count - 1
        }

        var directed: [(Int, Int)] = []
        for (index, segment) in segments.enumerated() {
            let splits = hits[index].sorted { $0.t < $1.t }
            var points = [segment.start]
            var lastT: CGFloat = 0
            for hit in splits where hit.t - lastT > 1e-5 && hit.t < 1 - 1e-5 {
                points.append(hit.point)
                lastT = hit.t
            }
            points.append(segment.end)
            for pointIndex in 0..<(points.count - 1) {
                let from = vertex(points[pointIndex])
                let to = vertex(points[pointIndex + 1])
                if from != to { directed.append((from, to)) }
            }
        }

        var boundary: [(Int, Int)] = []
        var seen = Set<String>()
        for (from, to) in directed {
            let start = vertices[from]
            let end = vertices[to]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = hypot(dx, dy)
            guard length > mergeDistance else { continue }
            let normalX = -dy / length
            let normalY = dx / length
            let midX = (start.x + end.x) / 2
            let midY = (start.y + end.y) / 2
            let distance = min(probe, max(0.01, length * 0.2))
            let left = CGPoint(x: midX + normalX * distance, y: midY + normalY * distance)
            let right = CGPoint(x: midX - normalX * distance, y: midY - normalY * distance)
            let insideLeft = insideAny(left, oriented)
            let insideRight = insideAny(right, oriented)
            guard insideLeft != insideRight else { continue }
            let edge = insideLeft ? (from, to) : (to, from)
            let key = "\(edge.0)->\(edge.1)"
            if seen.insert(key).inserted {
                boundary.append(edge)
            }
        }
        guard !boundary.isEmpty else { return nil }

        var outgoing: [Int: [Int]] = [:]
        var unused = Set<String>()
        for edge in boundary {
            outgoing[edge.0, default: []].append(edge.1)
            unused.insert("\(edge.0)->\(edge.1)")
        }

        var rings: [[CGPoint]] = []
        for edge in boundary {
            guard unused.contains("\(edge.0)->\(edge.1)") else { continue }
            var indices = [edge.0]
            var current = edge.0
            var next = edge.1
            var closed = false
            var steps = 0
            while steps <= boundary.count + 2 {
                steps += 1
                guard unused.remove("\(current)->\(next)") != nil else { break }
                indices.append(next)
                if next == edge.0 {
                    closed = true
                    break
                }
                let options = (outgoing[next] ?? []).filter { unused.contains("\(next)->\($0)") }
                guard let chosen = chooseNext(arrivedFrom: current, at: next, options: options, vertices: vertices) else {
                    break
                }
                current = next
                next = chosen
            }
            guard closed, indices.count >= 4 else { continue }
            indices.removeLast()
            let ring = cleaned(indices.map { vertices[$0] })
            guard abs(signedArea(ring)) > 0.4 else { continue }
            rings.append(signedArea(ring) < 0 ? Array(ring.reversed()) : ring)
        }
        guard !rings.isEmpty, unused.isEmpty else { return nil }
        return rings
    }

    /// The union should cover the largest piece and not grow past the pieces combined.
    private static func plausible(_ rings: [[CGPoint]], solids: [Contour]) -> Bool {
        let unionArea = rings.reduce(CGFloat(0)) { $0 + abs(signedArea($1)) }
        let largest = solids.map { abs($0.area) }.max() ?? 0
        let total = solids.reduce(CGFloat(0)) { $0 + abs($1.area) }
        return unionArea + 0.5 >= largest * 0.9 && unionArea <= total * 1.02 + 1
    }

    /// Next boundary edge. One choice is that edge. Several choices take the sharpest right turn,
    /// which keeps the filled side on the left.
    private static func chooseNext(arrivedFrom: Int, at: Int, options: [Int], vertices: [CGPoint]) -> Int? {
        guard let first = options.first else { return nil }
        if options.count == 1 { return first }
        let incoming = CGPoint(
            x: vertices[at].x - vertices[arrivedFrom].x,
            y: vertices[at].y - vertices[arrivedFrom].y
        )
        return options.min { left, right in
            clockwiseAngle(incoming, toward: vertices[left], from: vertices[at])
                < clockwiseAngle(incoming, toward: vertices[right], from: vertices[at])
        }
    }

    /// Clockwise angle from `incoming` to the segment that runs toward `toward`.
    private static func clockwiseAngle(_ incoming: CGPoint, toward: CGPoint, from: CGPoint) -> CGFloat {
        let outgoing = CGPoint(x: toward.x - from.x, y: toward.y - from.y)
        let cross = incoming.x * outgoing.y - incoming.y * outgoing.x
        let dot = incoming.x * outgoing.x + incoming.y * outgoing.y
        var angle = -atan2(cross, dot)
        if angle < 0 { angle += 2 * .pi }
        return angle
    }

    /// True when `point` is inside any ring.
    private static func insideAny(_ point: CGPoint, _ rings: [[CGPoint]]) -> Bool {
        rings.contains { ringContains(point, $0) }
    }

    /// Even-odd test. The sample is nudged off horizontal vertex rows.
    private static func ringContains(_ point: CGPoint, _ ring: [CGPoint]) -> Bool {
        guard ring.count >= 3 else { return false }
        let y = point.y + 0.000017
        var inside = false
        var previous = ring.count - 1
        for index in ring.indices {
            let current = ring[index]
            let prior = ring[previous]
            if (current.y > y) != (prior.y > y) {
                let x = (prior.x - current.x) * (y - current.y) / (prior.y - current.y) + current.x
                if point.x < x { inside.toggle() }
            }
            previous = index
        }
        return inside
    }

    /// True when `point` lies on a segment of `ring`.
    private static func onRing(_ point: CGPoint, _ ring: [CGPoint]) -> Bool {
        for index in ring.indices {
            let start = ring[index]
            let end = ring[(index + 1) % ring.count]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = hypot(dx, dy)
            guard length > 1e-6 else { continue }
            let t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / (length * length)
            guard t >= -0.01, t <= 1.01 else { continue }
            let clamped = min(1, max(0, t))
            let closest = CGPoint(x: start.x + dx * clamped, y: start.y + dy * clamped)
            if hypot(closest.x - point.x, closest.y - point.y) < 0.05 { return true }
        }
        return false
    }

    /// A crossing or a T-junction of two segments. Vertex-to-vertex contact is ignored.
    private struct SegmentHit {
        var t: CGFloat
        var u: CGFloat
        var point: CGPoint
    }

    private static func segmentHit(
        _ start: CGPoint,
        _ end: CGPoint,
        _ otherStart: CGPoint,
        _ otherEnd: CGPoint
    ) -> SegmentHit? {
        let rx = end.x - start.x
        let ry = end.y - start.y
        let sx = otherEnd.x - otherStart.x
        let sy = otherEnd.y - otherStart.y
        let denom = rx * sy - ry * sx
        if abs(denom) < 1e-9 { return nil }
        let qpx = otherStart.x - start.x
        let qpy = otherStart.y - start.y
        let t = (qpx * sy - qpy * sx) / denom
        let u = (qpx * ry - qpy * rx) / denom
        let eps: CGFloat = 1e-5
        guard t >= -eps, t <= 1 + eps, u >= -eps, u <= 1 + eps else { return nil }
        let tInterior = t > eps && t < 1 - eps
        let uInterior = u > eps && u < 1 - eps
        guard tInterior || uInterior else { return nil }
        let clampedT = min(1, max(0, t))
        return SegmentHit(
            t: clampedT,
            u: min(1, max(0, u)),
            point: CGPoint(x: start.x + rx * clampedT, y: start.y + ry * clampedT)
        )
    }

    /// Average of the ring. For a counter this lands in the opening.
    private static func interiorSample(_ ring: [CGPoint]) -> CGPoint? {
        guard !ring.isEmpty else { return nil }
        let total = ring.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: total.x / CGFloat(ring.count), y: total.y / CGFloat(ring.count))
    }

    /// Drops repeated points, including a closing point that repeats the start.
    private static func cleaned(_ points: [CGPoint]) -> [CGPoint] {
        var ring: [CGPoint] = []
        for point in points {
            if let last = ring.last, hypot(last.x - point.x, last.y - point.y) < mergeDistance { continue }
            ring.append(point)
        }
        if ring.count >= 2,
           hypot(ring[0].x - ring[ring.count - 1].x, ring[0].y - ring[ring.count - 1].y) < mergeDistance {
            ring.removeLast()
        }
        return ring
    }

    private static func bounds(_ ring: [CGPoint]) -> CGRect {
        guard let first = ring.first else { return .null }
        var box = CGRect(origin: first, size: .zero)
        for point in ring.dropFirst() {
            box = box.union(CGRect(origin: point, size: .zero))
        }
        return box
    }

    /// Positive when the ring runs counterclockwise with y up.
    private static func signedArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            sum += points[index].x * next.y - next.x * points[index].y
        }
        return sum / 2
    }

    /// Reverses a single closed subpath so its winding flips and the shape stays.
    private static func reversed(_ path: CGPath) -> CGPath {
        struct Command {
            var type: CGPathElementType
            var points: [CGPoint]
            var start: CGPoint
        }
        var commands: [Command] = []
        var cursor = CGPoint.zero
        path.applyWithBlock { element in
            let type = element.pointee.type
            let points = element.pointee.points
            switch type {
            case .moveToPoint:
                cursor = points[0]
            case .addLineToPoint:
                commands.append(Command(type: type, points: [points[0]], start: cursor))
                cursor = points[0]
            case .addQuadCurveToPoint:
                commands.append(Command(type: type, points: [points[0], points[1]], start: cursor))
                cursor = points[1]
            case .addCurveToPoint:
                commands.append(Command(type: type, points: [points[0], points[1], points[2]], start: cursor))
                cursor = points[2]
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
        let result = CGMutablePath()
        result.move(to: cursor)
        for command in commands.reversed() {
            switch command.type {
            case .addLineToPoint:
                result.addLine(to: command.start)
            case .addQuadCurveToPoint:
                result.addQuadCurve(to: command.start, control: command.points[0])
            case .addCurveToPoint:
                result.addCurve(to: command.start, control1: command.points[1], control2: command.points[0])
            default:
                break
            }
        }
        result.closeSubpath()
        return result
    }

    private static func appendLine(to point: CGPoint, into ring: inout [CGPoint]) {
        if let last = ring.last, hypot(last.x - point.x, last.y - point.y) < 1e-6 { return }
        ring.append(point)
    }

    private static func flattenQuad(
        from: CGPoint,
        control: CGPoint,
        to: CGPoint,
        into ring: inout [CGPoint],
        depth: Int = 0
    ) {
        if depth > 14 || curveDeviation(from, control, to) <= flatness {
            ring.append(to)
            return
        }
        let leftControl = midpoint(from, control)
        let rightControl = midpoint(control, to)
        let mid = midpoint(leftControl, rightControl)
        flattenQuad(from: from, control: leftControl, to: mid, into: &ring, depth: depth + 1)
        flattenQuad(from: mid, control: rightControl, to: to, into: &ring, depth: depth + 1)
    }

    private static func flattenCubic(
        from: CGPoint,
        control1: CGPoint,
        control2: CGPoint,
        to: CGPoint,
        into ring: inout [CGPoint],
        depth: Int = 0
    ) {
        let deviation = max(curveDeviation(from, control1, to), curveDeviation(from, control2, to))
        if depth > 14 || deviation <= flatness {
            ring.append(to)
            return
        }
        let p01 = midpoint(from, control1)
        let p12 = midpoint(control1, control2)
        let p23 = midpoint(control2, to)
        let p012 = midpoint(p01, p12)
        let p123 = midpoint(p12, p23)
        let mid = midpoint(p012, p123)
        flattenCubic(from: from, control1: p01, control2: p012, to: mid, into: &ring, depth: depth + 1)
        flattenCubic(from: mid, control1: p123, control2: p23, to: to, into: &ring, depth: depth + 1)
    }

    /// Distance from `control` to the chord `start`–`end`.
    private static func curveDeviation(_ start: CGPoint, _ control: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        if length < 1e-6 { return hypot(control.x - start.x, control.y - start.y) }
        return abs((control.x - start.x) * dy - (control.y - start.y) * dx) / length
    }

    private static func midpoint(_ start: CGPoint, _ end: CGPoint) -> CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }
}
