//
//  WashFiller.swift
//  Sketchy
//
//  Crayon wash: separate strokes, each with its own angle, width, trim, and bow.
//

import Foundation

/// Fills a shape with individual crayon-wash strokes.
///
/// `Options.washPasses` lists the bands. When it is nil, `.wash` uses `WashPass.sky`.
/// Each stroke is clipped to the polygon with the even-odd rule, then drawn with
/// `WashStrokeBuilder` so a contour fill can run the same centerline recipe.
public struct WashFiller: FillGenerator {
    public init() {}

    public func fillPolygon(points: [[Float]], options: Options) -> OperationSet? {
        let sets = fillPolygonSets(points: points, options: options)
        guard let first = sets.first else { return nil }
        if sets.count == 1 { return first }
        return OperationSet(
            type: .fillSketch,
            operations: sets.flatMap(\.operations),
            path: nil,
            size: nil,
            fillLineScale: first.fillLineScale,
            opacityScale: first.opacityScale
        )
    }

    public func fillPolygonSets(points: [[Float]], options: Options) -> [OperationSet] {
        let polygon = points.map { ContourPoint(x: $0[0], y: $0[1]) }
        guard polygon.count >= 3 else { return [] }
        let passes = options.washPasses ?? WashPass.sky
        var sets: [OperationSet] = []
        for pass in passes {
            sets.append(contentsOf: paint(
                polygon: polygon,
                pass: pass,
                angle: options.fillAngle,
                seed: options.seed ?? pass.seed
            ))
        }
        return sets
    }

    public func fillEllipse(cx: Float, cy: Float, rx: Float, ry: Float, options: Options) -> OperationSet? {
        let sets = fillEllipseSets(cx: cx, cy: cy, rx: rx, ry: ry, options: options)
        return sets.first
    }

    public func fillEllipseSets(cx: Float, cy: Float, rx: Float, ry: Float, options: Options) -> [OperationSet] {
        let steps = 80
        let points: [[Float]] = (0..<steps).map { index in
            let angle = Float(index) / Float(steps) * 2 * .pi
            return [cx + rx * cos(angle), cy + ry * sin(angle)]
        }
        return fillPolygonSets(points: points, options: options)
    }

    private func paint(
        polygon: [ContourPoint],
        pass: WashPass,
        angle: Float,
        seed: UInt64
    ) -> [OperationSet] {
        let base = angle * .pi / 180
        let guide = LineFrame(angle: base)
        let projections = polygon.map { guide.perp($0) }
        guard let minP = projections.min(), let maxP = projections.max(), maxP - minP > 1 else { return [] }
        let anchorAlong = guide.along(polygonCentroid(polygon))

        var random = WashRandom(seed: ContourField.mix(seed, Int(pass.seed & 0x7fff_ffff)))
        var buckets: [BucketKey: Bucket] = [:]
        var index = 0
        var perp = minP
        while perp <= maxP && index < 400 {
            index += 1
            let step = pass.spacingMin + random.unit() * pass.spacingSpan
            let fraction = (perp - minP) / max(maxP - minP, 0.001)
            perp += step
            let scatter = (random.unit() - 0.5) * pass.angleSpread * .pi / 180
            let frame = LineFrame(angle: base + scatter)
            let baseHere = minP + fraction * (maxP - minP) + (random.unit() - 0.5) * 10
            let anchor = guide.point(along: anchorAlong, perp: baseHere)
            let here = frame.perp(anchor)
            let hits = intersections(polygon: polygon, frame: frame, here: here)
            guard hits.count >= 2 else { continue }
            let width = pass.widthMin + random.unit() * pass.widthSpan
            let opacity = min(1, max(0, pass.opacityMin + random.unit() * pass.opacitySpan))
            var pair = 0
            while pair + 1 < hits.count {
                let lo = hits[pair]
                let hi = hits[pair + 1]
                pair += 2
                let trimA = endInset(pass: pass, width: width, random: &random)
                let trimB = endInset(pass: pass, width: width, random: &random)
                let from = lo + trimA
                let to = hi - trimB
                guard to - from >= pass.minLength else { continue }
                let bow = (random.unit() - 0.5) * pass.bow
                let samples = sineStroke(frame: frame, here: here, from: from, to: to, bow: bow)
                let slotSeed = ContourField.mix(ContourField.mix(seed, Int(pass.seed & 0x7fff_ffff)), index * 19 + pair)
                let operations = WashStrokeBuilder.operations(points: samples, seed: slotSeed, pass: pass)
                guard !operations.isEmpty else { continue }
                let key = BucketKey(
                    width: (width * 2).rounded() / 2,
                    opacity: (opacity * 50).rounded() / 50
                )
                var bucket = buckets[key] ?? Bucket(width: key.width, opacity: key.opacity, operations: [])
                bucket.operations.append(contentsOf: operations)
                buckets[key] = bucket
            }
        }

        return buckets.keys.sorted().compactMap { key in
            guard let bucket = buckets[key], !bucket.operations.isEmpty else { return nil }
            return OperationSet(
                type: .fillSketch,
                operations: bucket.operations,
                path: nil,
                size: nil,
                fillLineWidth: bucket.width,
                opacityScale: bucket.opacity
            )
        }
    }

    private func polygonCentroid(_ polygon: [ContourPoint]) -> ContourPoint {
        var x: Float = 0
        var y: Float = 0
        for point in polygon {
            x += point.x
            y += point.y
        }
        let count = Float(polygon.count)
        return ContourPoint(x: x / count, y: y / count)
    }

    private func endInset(pass: WashPass, width: Float, random: inout WashRandom) -> Float {
        let stretch: Float = random.unit() < 0.28 ? random.unit() * pass.trimMax * 0.7 : 0
        return width / 2 + 4 + random.unit() * pass.trimMax + stretch
    }

    private func sineStroke(
        frame: LineFrame,
        here: Float,
        from: Float,
        to: Float,
        bow: Float
    ) -> [[Float]] {
        let steps = 9
        return (0...steps).map { step in
            let t = Float(step) / Float(steps)
            let along = from + (to - from) * t
            let side = sin(t * .pi) * bow + sin(t * .pi * 2) * bow * 0.35
            let point = frame.point(along: along, perp: here + side)
            return [point.x, point.y]
        }
    }

    /// Even-odd crossings of an infinite line with the polygon, sorted along the line.
    private func intersections(polygon: [ContourPoint], frame: LineFrame, here: Float) -> [Float] {
        var hits: [Float] = []
        let count = polygon.count
        for index in 0..<count {
            let a = polygon[index]
            let b = polygon[(index + 1) % count]
            let d1 = frame.perp(a)
            let d2 = frame.perp(b)
            let den = d2 - d1
            if abs(den) < 1e-5 { continue }
            let t = (here - d1) / den
            if t < -0.001 || t > 1.001 { continue }
            let along = frame.along(a) + (frame.along(b) - frame.along(a)) * min(1, max(0, t))
            if let last = hits.last, abs(last - along) < 0.6 { continue }
            hits.append(along)
        }
        hits.sort()
        var unique: [Float] = []
        for hit in hits where unique.last.map({ abs($0 - hit) > 0.6 }) ?? true {
            unique.append(hit)
        }
        if unique.count % 2 == 1 { unique.removeLast() }
        return unique
    }

    private struct BucketKey: Hashable, Comparable {
        var width: Float
        var opacity: Float

        static func < (lhs: BucketKey, rhs: BucketKey) -> Bool {
            if lhs.width != rhs.width { return lhs.width < rhs.width }
            return lhs.opacity < rhs.opacity
        }
    }

    private struct Bucket {
        var width: Float
        var opacity: Float
        var operations: [Operation]
    }
}

private struct LineFrame {
    var dx: Float
    var dy: Float
    var px: Float
    var py: Float

    init(angle: Float) {
        dx = cos(angle)
        dy = sin(angle)
        px = -dy
        py = dx
    }

    func along(_ point: ContourPoint) -> Float {
        point.x * dx + point.y * dy
    }

    func perp(_ point: ContourPoint) -> Float {
        point.x * px + point.y * py
    }

    func point(along: Float, perp: Float) -> ContourPoint {
        ContourPoint(x: dx * along + px * perp, y: dy * along + py * perp)
    }
}
