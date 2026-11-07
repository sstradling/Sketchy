//
//  SilhouetteUnion.swift
//  Sketchy
//
//  Vector union of sticker silhouettes.
//
//  Route: SketchGroup collects one ring per closed outline, then
//  SilhouetteUnion.combine merges overlaps before StickerBackingBuilder
//  offsets the shared sheet. Distant components stay separate. A point
//  contact does not grow a bridge.
//

import CoreGraphics

/// Closed rings that participate in one sticker sheet.
struct SilhouetteRing {
    var points: [CGPoint]
    /// Rings from the same shape share an id. Even-odd nesting is per shape.
    var shape: Int
    var isHole: Bool
}

enum SilhouetteUnion {

    /// Merges overlapping exteriors and keeps uncovered holes.
    ///
    /// The result is one or more simple rings. Exteriors do not overlap.
    /// A hole is kept only where no shape covers it. Components that do not
    /// overlap stay separate; the gap between them is not filled.
    static func combine(_ rings: [SilhouetteRing]) -> [SilhouetteRing] {
        let shapes = Dictionary(grouping: rings, by: \.shape)
        let edges = boundaryEdges(shapes: shapes)
        let loops = chain(edges)
        return loops.enumerated().map { index, loop in
            SilhouetteRing(points: loop.points, shape: index, isHole: loop.isHole)
        }
    }

    private struct Loop {
        var points: [CGPoint]
        var isHole: Bool
    }

    private struct Edge {
        var start: CGPoint
        var end: CGPoint
    }

    /// Pieces of outline with the filled side on the left.
    private static func boundaryEdges(shapes: [Int: [SilhouetteRing]]) -> [Edge] {
        var segments: [(CGPoint, CGPoint)] = []
        for ring in shapes.values.flatMap({ $0 }) where ring.points.count >= 3 {
            let points = ring.points
            for index in 0..<points.count {
                let start = points[index]
                let end = points[(index + 1) % points.count]
                if hypot(end.x - start.x, end.y - start.y) > 0.05 {
                    segments.append((start, end))
                }
            }
        }
        let pieces = split(segments)
        var edges: [Edge] = []
        for (start, end) in pieces {
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = hypot(dx, dy)
            guard length > 0.05 else { continue }
            let offset = min(0.35, length * 0.25)
            let left = CGPoint(
                x: (start.x + end.x) * 0.5 + (-dy / length) * offset,
                y: (start.y + end.y) * 0.5 + (dx / length) * offset
            )
            let right = CGPoint(
                x: (start.x + end.x) * 0.5 - (-dy / length) * offset,
                y: (start.y + end.y) * 0.5 - (dx / length) * offset
            )
            let coverLeft = covered(left, shapes: shapes)
            let coverRight = covered(right, shapes: shapes)
            if coverLeft && !coverRight {
                edges.append(Edge(start: start, end: end))
            } else if coverRight && !coverLeft {
                edges.append(Edge(start: end, end: start))
            }
        }
        return dedupe(edges)
    }

    private static func dedupe(_ edges: [Edge]) -> [Edge] {
        struct Key: Hashable {
            var ax: Int
            var ay: Int
            var bx: Int
            var by: Int
        }
        func quantize(_ value: CGFloat) -> Int {
            Int((value / 0.25).rounded())
        }
        var seen: Set<Key> = []
        return edges.filter { edge in
            let key = Key(
                ax: quantize(edge.start.x),
                ay: quantize(edge.start.y),
                bx: quantize(edge.end.x),
                by: quantize(edge.end.y)
            )
            return seen.insert(key).inserted
        }
    }

    /// Cuts where two edges lie on the same line and overlap. Crossing edges use `intersection`.
    private static func collinearCuts(
        _ first: (CGPoint, CGPoint),
        _ second: (CGPoint, CGPoint)
    ) -> [(CGFloat, CGFloat)] {
        let r = CGPoint(x: first.1.x - first.0.x, y: first.1.y - first.0.y)
        let s = CGPoint(x: second.1.x - second.0.x, y: second.1.y - second.0.y)
        let length = hypot(r.x, r.y)
        let other = hypot(s.x, s.y)
        guard length > 0.05, other > 0.05 else { return [] }
        let cross = r.x * s.y - r.y * s.x
        guard abs(cross) < 0.02 * length * other else { return [] }
        let fromStart = CGPoint(x: second.0.x - first.0.x, y: second.0.y - first.0.y)
        let fromEnd = CGPoint(x: second.1.x - first.0.x, y: second.1.y - first.0.y)
        guard abs(fromStart.x * r.y - fromStart.y * r.x) / length < 0.4 else { return [] }
        let t0 = (fromStart.x * r.x + fromStart.y * r.y) / (length * length)
        let t1 = (fromEnd.x * r.x + fromEnd.y * r.y) / (length * length)
        let low = min(t0, t1)
        let high = max(t0, t1)
        guard high > 0.001, low < 0.999 else { return [] }
        let u0 = (fromStart.x * s.x + fromStart.y * s.y) / (other * other)
        return [(t0, u0), (t1, u0 + (t1 - t0) * length / other)]
    }

    /// A point is ink when any one shape covers it an odd number of times.
    private static func covered(_ point: CGPoint, shapes: [Int: [SilhouetteRing]]) -> Bool {
        for rings in shapes.values {
            let hits = rings.filter { contains(point, ring: $0.points) }.count
            if hits % 2 == 1 { return true }
        }
        return false
    }

    private static func split(_ segments: [(CGPoint, CGPoint)]) -> [(CGPoint, CGPoint)] {
        var cuts: [[CGFloat]] = Array(repeating: [0, 1], count: segments.count)
        for index in segments.indices {
            for other in (index + 1)..<segments.count {
                if let hit = intersection(segments[index], segments[other]) {
                    if hit.0 > 0.001 && hit.0 < 0.999 { cuts[index].append(hit.0) }
                    if hit.1 > 0.001 && hit.1 < 0.999 { cuts[other].append(hit.1) }
                }
                for mark in collinearCuts(segments[index], segments[other]) {
                    if mark.0 > 0.001 && mark.0 < 0.999 { cuts[index].append(mark.0) }
                    if mark.1 > 0.001 && mark.1 < 0.999 { cuts[other].append(mark.1) }
                }
            }
        }
        var pieces: [(CGPoint, CGPoint)] = []
        for index in segments.indices {
            let (start, end) = segments[index]
            let marks = cuts[index].sorted()
            var previous = marks[0]
            for mark in marks.dropFirst() where mark - previous > 0.002 {
                pieces.append((
                    point(start, end, previous),
                    point(start, end, mark)
                ))
                previous = mark
            }
        }
        return pieces
    }

    private static func chain(_ edges: [Edge]) -> [Loop] {
        struct Key: Hashable {
            var x: Int
            var y: Int
        }
        func key(_ point: CGPoint) -> Key {
            Key(x: Int((point.x / 0.2).rounded()), y: Int((point.y / 0.2).rounded()))
        }
        var unused: [Key: [Edge]] = [:]
        for edge in edges {
            unused[key(edge.start), default: []].append(edge)
        }
        var loops: [Loop] = []
        let keys = Array(unused.keys)
        for startKey in keys {
            while var edge = unused[startKey]?.popLast() {
                var points = [edge.start]
                var guardSteps = 0
                while guardSteps < edges.count + 2 {
                    points.append(edge.end)
                    let endKey = key(edge.end)
                    if endKey == startKey { break }
                    guard let options = unused[endKey], !options.isEmpty else { break }
                    let incoming = CGPoint(x: edge.end.x - edge.start.x, y: edge.end.y - edge.start.y)
                    var bestIndex = 0
                    var bestTurn = CGFloat.greatestFiniteMagnitude
                    for index in options.indices {
                        let candidate = options[index]
                        let outgoing = CGPoint(
                            x: candidate.end.x - candidate.start.x,
                            y: candidate.end.y - candidate.start.y
                        )
                        let turn = atan2(
                            incoming.x * outgoing.y - incoming.y * outgoing.x,
                            incoming.x * outgoing.x + incoming.y * outgoing.y
                        )
                        // Interior is on the left. The next boundary edge is the sharpest right turn.
                        let score = turn >= 0 ? turn : turn + 2 * .pi
                        if score < bestTurn {
                            bestTurn = score
                            bestIndex = index
                        }
                    }
                    edge = options[bestIndex]
                    unused[endKey]?.remove(at: bestIndex)
                    guardSteps += 1
                }
                if points.count >= 4, key(points[points.count - 1]) == startKey {
                    points.removeLast()
                    let hole = signedArea(points) < 0
                    loops.append(Loop(points: points, isHole: hole))
                }
            }
        }
        return loops.filter { abs(signedArea($0.points)) > 4 }
    }

    private static func intersection(
        _ first: (CGPoint, CGPoint),
        _ second: (CGPoint, CGPoint)
    ) -> (CGFloat, CGFloat)? {
        let r = CGPoint(x: first.1.x - first.0.x, y: first.1.y - first.0.y)
        let s = CGPoint(x: second.1.x - second.0.x, y: second.1.y - second.0.y)
        let denominator = r.x * s.y - r.y * s.x
        guard abs(denominator) > 1e-6 else { return nil }
        let qp = CGPoint(x: second.0.x - first.0.x, y: second.0.y - first.0.y)
        let t = (qp.x * s.y - qp.y * s.x) / denominator
        let u = (qp.x * r.y - qp.y * r.x) / denominator
        guard t > -0.001, t < 1.001, u > -0.001, u < 1.001 else { return nil }
        return (min(1, max(0, t)), min(1, max(0, u)))
    }

    private static func point(_ start: CGPoint, _ end: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
    }

    private static func contains(_ point: CGPoint, ring: [CGPoint]) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var previous = ring.count - 1
        for index in ring.indices {
            let currentY = ring[index].y
            let previousY = ring[previous].y
            let crosses = (currentY > point.y) != (previousY > point.y)
            if crosses {
                let x = (ring[previous].x - ring[index].x) * (point.y - currentY)
                    / (previousY - currentY) + ring[index].x
                if point.x < x { inside.toggle() }
            }
            previous = index
        }
        return inside
    }

    private static func signedArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var area: CGFloat = 0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            area += points[index].x * next.y - next.x * points[index].y
        }
        return area * 0.5
    }
}
