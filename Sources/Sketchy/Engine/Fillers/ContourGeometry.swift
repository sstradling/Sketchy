//
//  ContourGeometry.swift
//  Sketchy
//
//  Clipped contour strokes before roughness is applied.
//
//  A stroke is the guide curve at one offset, clipped to the polygon with the
//  even-odd rule, then blended toward its chord. Intensity 0 keeps the chord.
//  Intensity 1 keeps the guide curve. Values above 1 exaggerate the bow.
//  Graduation evaluates that intensity at each sample from a projection across
//  the shape, so one stroke can be straight on one side and bowed on the other.
//

import Foundation

struct ContourStroke: Equatable {
    var slot: Int
    var offset: Float
    var scale: Float
    var points: [ContourPoint]
}

struct ContourPlan: Equatable {
    var strokes: [ContourStroke]
    /// Phase distance that brings every slot back to where it started.
    var period: Float
    var gap: Float
    var slotCount: Int
    /// Unit vector from the guide side of the shape toward the far side.
    var travel: ContourPoint
    /// Slot shift after wrapping, in `0..<slotCount`. Exposed for tests.
    var phaseSlots: Float
}

enum ContourGeometry {
    static func plan(polygon raw: [[Float]], options: Options) -> ContourPlan {
        let polygon = raw.map { ContourPoint(x: $0[0], y: $0[1]) }
        guard polygon.count >= 3 else { return .empty }
        let scan = Scan(polygon: polygon, options: options)
        guard let scan else { return .empty }

        let gap = max(options.computedHachureGap, 0.5)
        let count = min(360, max(2, Int((scan.range.span / gap).rounded())))
        let travel = scan.travel
        let drift = driftComponent(options: options, travel: travel)
        let period = Float(count) * gap / max(abs(drift.along), 0.001)
        let phase = wrapped(drift.phase, period: period)
        let phaseSlots = slotShift(phase: phase, along: drift.along, gap: gap, count: count)
        let field = IntensityField(polygon: polygon, options: options)
        let falloff = min(1, max(0, options.contourFalloff))

        var strokes: [ContourStroke] = []
        for placement in ContourField.placements(count: count, falloff: falloff, phaseSlots: phaseSlots) {
            let offset = scan.range.position(placement.u)
            let scale = widthScale(u: placement.u, falloff: falloff)
            let minChord = max(6, options.effectiveFillWeight * 1.5) * max(0.35, scale)
            let pieces = scan.pieces(at: offset, polygon: polygon)
            for piece in pieces {
                let bowed = bow(piece, field: field)
                guard chord(bowed) >= minChord else { continue }
                strokes.append(ContourStroke(
                    slot: placement.slot,
                    offset: offset,
                    scale: scale,
                    points: bowed
                ))
            }
        }

        return ContourPlan(
            strokes: strokes,
            period: period,
            gap: gap,
            slotCount: count,
            travel: travel,
            phaseSlots: phaseSlots
        )
    }

    /// `0.22` at the guide when falloff is 1, and `1` at the far side.
    static func widthScale(u: Float, falloff: Float) -> Float {
        let proximity = 1 - min(1, max(0, u))
        return 1 - falloff * proximity * (1 - 0.22)
    }
}

private extension ContourPlan {
    static let empty = ContourPlan(
        strokes: [],
        period: 1,
        gap: 1,
        slotCount: 1,
        travel: ContourPoint(x: 0, y: 1),
        phaseSlots: 0
    )
}

// MARK: - Intensity

private struct IntensityField {
    var start: Float
    var end: Float
    var dirX: Float
    var dirY: Float
    var minP: Float
    var span: Float
    var easing: ContourEasing

    init(polygon: [ContourPoint], options: Options) {
        start = options.contourIntensityStart ?? options.contourIntensity
        end = options.contourIntensityEnd ?? options.contourIntensity
        easing = options.contourEasing
        let radians = options.contourGradientAngle * Float.pi / 180
        dirX = cos(radians)
        dirY = sin(radians)
        var low = Float.greatestFiniteMagnitude
        var high = -Float.greatestFiniteMagnitude
        for point in polygon {
            let projection = point.x * dirX + point.y * dirY
            low = min(low, projection)
            high = max(high, projection)
        }
        minP = low
        span = max(high - low, 0.001)
    }

    func value(at point: ContourPoint) -> Float {
        let t = min(1, max(0, (point.x * dirX + point.y * dirY - minP) / span))
        return start + (end - start) * easing.value(t)
    }
}

private func bow(_ points: [ContourPoint], field: IntensityField) -> [ContourPoint] {
    guard points.count >= 2, let first = points.first, let last = points.last else { return [] }
    if hypot(first.x - last.x, first.y - last.y) < 0.5, points.count > 8 {
        let mid = points.count / 2
        return bow(Array(points[0...mid]), field: field) + bow(Array(points[mid...]), field: field)
    }
    let count = points.count
    return points.enumerated().map { index, point in
        let u = Float(index) / Float(count - 1)
        let chord = ContourPoint(
            x: first.x + (last.x - first.x) * u,
            y: first.y + (last.y - first.y) * u
        )
        let k = field.value(at: point)
        return ContourPoint(
            x: chord.x + (point.x - chord.x) * k,
            y: chord.y + (point.y - chord.y) * k
        )
    }
}

private func chord(_ points: [ContourPoint]) -> Float {
    guard let first = points.first, let last = points.last else { return 0 }
    return hypot(last.x - first.x, last.y - first.y)
}

/// Slot shift in `0..<count`. A value within 1e-4 of an integer snaps to it
/// so a full period lands on the same slots instead of a float hair away.
private func slotShift(phase: Float, along: Float, gap: Float, count: Int) -> Float {
    guard count > 0, gap > 0 else { return 0 }
    var slots = Double(phase) * Double(along) / Double(gap)
    slots = slots.truncatingRemainder(dividingBy: Double(count))
    if slots < 0 {
        slots += Double(count)
    }
    let nearest = slots.rounded()
    if abs(slots - nearest) < 1e-4 {
        slots = nearest.truncatingRemainder(dividingBy: Double(count))
        if slots < 0 { slots += Double(count) }
    }
    return Float(slots)
}

private func wrapped(_ phase: Float, period: Float) -> Float {
    guard period > 0, period.isFinite, abs(phase) > period else { return phase }
    let turns = floor(phase / period)
    return phase - turns * period
}

private func driftComponent(options: Options, travel: ContourPoint) -> (along: Float, phase: Float) {
    guard let drift = options.contourDrift else { return (1, 0) }
    let radians = drift.angle * Float.pi / 180
    let along = cos(radians) * travel.x + sin(radians) * travel.y
    return (along, drift.phase)
}

// MARK: - Scan

private struct ScanRange {
    var low: Float
    var high: Float
    var guideAtLow: Bool

    var span: Float { max(high - low, 0.001) }

    func position(_ u: Float) -> Float {
        let u = min(1, max(0, u))
        return guideAtLow ? low + u * span : high - u * span
    }
}

private struct Scan {
    var travel: ContourPoint
    var range: ScanRange
    var clip: (Float, [ContourPoint]) -> [[ContourPoint]]

    init(
        travel: ContourPoint,
        range: ScanRange,
        clip: @escaping (Float, [ContourPoint]) -> [[ContourPoint]]
    ) {
        self.travel = travel
        self.range = range
        self.clip = clip
    }

    init?(polygon: [ContourPoint], options: Options) {
        switch options.contourGuide {
        case let .arc(center, radius):
            guard let scan = Scan.arc(center: center, guideRadius: radius, polygon: polygon) else { return nil }
            self = scan
        case let .polyline(points, closed):
            guard points.count >= 2,
                  let scan = Scan.polyline(points: points, closed: closed, polygon: polygon) else {
                return nil
            }
            self = scan
        case nil:
            guard let scan = Scan.lines(angle: options.fillAngle, polygon: polygon) else { return nil }
            self = scan
        }
    }

    func pieces(at offset: Float, polygon: [ContourPoint]) -> [[ContourPoint]] {
        clip(offset, polygon)
    }

    static func arc(center: ContourPoint, guideRadius: Float, polygon: [ContourPoint]) -> Scan? {
        let centroid = centroid(of: polygon)
        var radial = ContourPoint(x: centroid.x - center.x, y: centroid.y - center.y)
        if hypot(radial.x, radial.y) < 1 {
            radial = ContourPoint(x: 0, y: 1)
        } else {
            radial = normalize(radial)
        }
        var low = Float.greatestFiniteMagnitude
        var high: Float = 0
        if contains(center, polygon: polygon) {
            low = 0
        }
        for point in polygon {
            let distance = hypot(point.x - center.x, point.y - center.y)
            low = min(low, distance)
            high = max(high, distance)
        }
        let count = polygon.count
        for index in 0..<count {
            let distance = distanceToSegment(center, polygon[index], polygon[(index + 1) % count])
            low = min(low, distance)
        }
        guard high - low > 0.5 else { return nil }
        let guideAtLow = abs(low - guideRadius) <= abs(high - guideRadius)
        let range = ScanRange(low: low, high: high, guideAtLow: guideAtLow)
        let travel = normalize(ContourPoint(
            x: radial.x * (range.position(1) - range.position(0)),
            y: radial.y * (range.position(1) - range.position(0))
        ))
        return Scan(travel: travel, range: range) { offset, polygon in
            circlePieces(center: center, radius: offset, radial: radial, polygon: polygon)
        }
    }

    static func lines(angle: Float, polygon: [ContourPoint]) -> Scan? {
        let radians = angle * Float.pi / 180
        let tangent = ContourPoint(x: cos(radians), y: sin(radians))
        let axis = ContourPoint(x: -tangent.y, y: tangent.x)
        let offsets = polygon.map { $0.x * axis.x + $0.y * axis.y }
        guard let low = offsets.min(), let high = offsets.max(), high - low > 0.5 else { return nil }
        let range = ScanRange(low: low, high: high, guideAtLow: true)
        let centroid = centroid(of: polygon)
        return Scan(travel: axis, range: range) { offset, polygon in
            let shift = offset - (centroid.x * axis.x + centroid.y * axis.y)
            let origin = ContourPoint(
                x: centroid.x + axis.x * shift,
                y: centroid.y + axis.y * shift
            )
            let reach = diagonal(of: polygon) + 8
            let start = ContourPoint(
                x: origin.x - tangent.x * reach,
                y: origin.y - tangent.y * reach
            )
            let end = ContourPoint(
                x: origin.x + tangent.x * reach,
                y: origin.y + tangent.y * reach
            )
            return clipChain([start, end], closed: false, polygon: polygon)
        }
    }

    static func polyline(points: [ContourPoint], closed: Bool, polygon: [ContourPoint]) -> Scan? {
        let distances = polygon.map { signedDistance($0, guide: points, closed: closed) }
        guard let low = distances.min(), let high = distances.max(), high - low > 0.5 else { return nil }
        let guideAtLow = abs(low) <= abs(high)
        let range = ScanRange(low: low, high: high, guideAtLow: guideAtLow)
        let centroid = centroid(of: polygon)
        let (_, normal) = closestFrame(to: centroid, guide: points, closed: closed)
        let reach = diagonal(of: polygon) + 8
        return Scan(
            travel: normalize(ContourPoint(
                x: normal.x * (range.position(1) - range.position(0)),
                y: normal.y * (range.position(1) - range.position(0))
            )),
            range: range
        ) { offset, polygon in
            var chain = offsetCurve(points, distance: offset, closed: closed)
            if !closed {
                chain = extend(chain, by: reach)
            }
            return clipChain(chain, closed: closed, polygon: polygon)
        }
    }
}

// MARK: - Circle clip

private func circlePieces(
    center: ContourPoint,
    radius: Float,
    radial: ContourPoint,
    polygon: [ContourPoint]
) -> [[ContourPoint]] {
    guard radius > 0.5 else { return [] }
    var hits: [(angle: Float, point: ContourPoint)] = []
    let count = polygon.count
    for index in 0..<count {
        let start = polygon[index]
        let end = polygon[(index + 1) % count]
        for hit in circleSegmentHits(center: center, radius: radius, a: start, b: end) {
            hits.append((atan2(hit.y - center.y, hit.x - center.x), hit))
        }
    }
    hits = dedupCircular(hits)
    if hits.isEmpty {
        let probe = ContourPoint(x: center.x + radius, y: center.y)
        guard contains(probe, polygon: polygon) else { return [] }
        let base = atan2(radial.y, radial.x)
        return [
            sampleArc(center: center, radius: radius, from: base, to: base + .pi),
            sampleArc(center: center, radius: radius, from: base + .pi, to: base + 2 * .pi)
        ]
    }
    guard hits.count >= 2 else { return [] }

    var pieces: [[ContourPoint]] = []
    for index in 0..<hits.count {
        let start = hits[index].angle
        var stop = hits[(index + 1) % hits.count].angle
        if index == hits.count - 1 || stop < start {
            stop += 2 * .pi
        }
        let mid = (start + stop) / 2
        let probe = ContourPoint(
            x: center.x + radius * cos(mid),
            y: center.y + radius * sin(mid)
        )
        guard contains(probe, polygon: polygon) else { continue }
        pieces.append(sampleArc(center: center, radius: radius, from: start, to: stop))
    }
    return pieces
}

private func sampleArc(center: ContourPoint, radius: Float, from start: Float, to stop: Float) -> [ContourPoint] {
    let sweep = max(0, stop - start)
    let steps = min(36, max(8, Int(sweep / (Float.pi / 28))))
    return (0...steps).map { step in
        let angle = start + sweep * Float(step) / Float(steps)
        return ContourPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        )
    }
}

private func circleSegmentHits(
    center: ContourPoint,
    radius: Float,
    a: ContourPoint,
    b: ContourPoint
) -> [ContourPoint] {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let fx = a.x - center.x
    let fy = a.y - center.y
    let aCoef = dx * dx + dy * dy
    guard aCoef > 1e-8 else { return [] }
    let bCoef = 2 * (fx * dx + fy * dy)
    let cCoef = fx * fx + fy * fy - radius * radius
    let discriminant = bCoef * bCoef - 4 * aCoef * cCoef
    guard discriminant >= 0 else { return [] }
    let root = sqrt(discriminant)
    var hits: [ContourPoint] = []
    for sign in [-1 as Float, 1] {
        let t = (-bCoef + sign * root) / (2 * aCoef)
        guard t >= -1e-4, t <= 1 + 1e-4 else { continue }
        let clamped = min(1, max(0, t))
        hits.append(ContourPoint(x: a.x + dx * clamped, y: a.y + dy * clamped))
    }
    return hits
}

private func dedupCircular(_ hits: [(angle: Float, point: ContourPoint)]) -> [(angle: Float, point: ContourPoint)] {
    var sorted = hits.sorted { $0.angle < $1.angle }
    var kept: [(angle: Float, point: ContourPoint)] = []
    for hit in sorted {
        if let last = kept.last, hypot(hit.point.x - last.point.x, hit.point.y - last.point.y) < 0.75 {
            continue
        }
        kept.append(hit)
    }
    if kept.count >= 2,
       hypot(kept[0].point.x - kept[kept.count - 1].point.x, kept[0].point.y - kept[kept.count - 1].point.y) < 0.75 {
        kept.removeLast()
    }
    sorted = kept
    return sorted
}

// MARK: - Chain clip

private func clipChain(_ chain: [ContourPoint], closed: Bool, polygon: [ContourPoint]) -> [[ContourPoint]] {
    guard chain.count >= 2 else { return [] }
    var work = chain
    if closed, let first = work.first, let last = work.last, hypot(first.x - last.x, first.y - last.y) > 0.05 {
        work.append(first)
    }
    var events: [(param: Float, point: ContourPoint)] = []
    let segments = work.count - 1
    let edges = polygon.count
    for index in 0..<segments {
        for edge in 0..<edges {
            guard let t = segmentHit(work[index], work[index + 1], polygon[edge], polygon[(edge + 1) % edges]) else {
                continue
            }
            events.append((
                Float(index) + t,
                ContourPoint(
                    x: work[index].x + (work[index + 1].x - work[index].x) * t,
                    y: work[index].y + (work[index + 1].y - work[index].y) * t
                )
            ))
        }
    }
    events = dedupEvents(events)

    var pieces: [[ContourPoint]] = []
    var inside = contains(work[0], polygon: polygon)
    var current: [ContourPoint] = inside ? [work[0]] : []
    var cursor: Float = 0
    for event in events {
        if inside {
            current.append(contentsOf: vertices(in: work, from: cursor, to: event.param))
            current.append(event.point)
            appendPiece(current, to: &pieces)
            current = []
        } else {
            current = [event.point]
        }
        inside.toggle()
        cursor = event.param
    }
    if inside {
        current.append(contentsOf: vertices(in: work, from: cursor, to: Float(segments)))
        current.append(work[segments])
        appendPiece(current, to: &pieces)
    }
    return pieces
}

private func vertices(in work: [ContourPoint], from start: Float, to end: Float) -> [ContourPoint] {
    let first = Int(floor(start)) + 1
    let last = min(Int(floor(end)), work.count - 1)
    guard last >= first else { return [] }
    return Array(work[first...last])
}

private func appendPiece(_ points: [ContourPoint], to pieces: inout [[ContourPoint]]) {
    var cleaned: [ContourPoint] = []
    for point in points {
        if let last = cleaned.last, hypot(point.x - last.x, point.y - last.y) < 0.15 {
            continue
        }
        cleaned.append(point)
    }
    if cleaned.count >= 2 {
        pieces.append(cleaned)
    }
}

private func dedupEvents(_ events: [(param: Float, point: ContourPoint)]) -> [(param: Float, point: ContourPoint)] {
    var kept: [(param: Float, point: ContourPoint)] = []
    for event in events.sorted(by: { $0.param < $1.param }) {
        if let last = kept.last, hypot(event.point.x - last.point.x, event.point.y - last.point.y) < 0.6 {
            continue
        }
        kept.append(event)
    }
    return kept
}

private func segmentHit(_ a: ContourPoint, _ b: ContourPoint, _ c: ContourPoint, _ d: ContourPoint) -> Float? {
    let rx = b.x - a.x
    let ry = b.y - a.y
    let sx = d.x - c.x
    let sy = d.y - c.y
    let denom = rx * sy - ry * sx
    if abs(denom) < 1e-6 { return nil }
    let qx = c.x - a.x
    let qy = c.y - a.y
    let t = (qx * sy - qy * sx) / denom
    let u = (qx * ry - qy * rx) / denom
    guard t >= -1e-4, t <= 1 + 1e-4, u >= -1e-4, u <= 1 + 1e-4 else { return nil }
    return min(1, max(0, t))
}

// MARK: - Guides

private func offsetCurve(_ points: [ContourPoint], distance: Float, closed: Bool) -> [ContourPoint] {
    let count = points.count
    return points.enumerated().map { index, point in
        let normal = vertexNormal(points, index: index, closed: closed)
        return ContourPoint(x: point.x + normal.x * distance, y: point.y + normal.y * distance)
    }
}

private func vertexNormal(_ points: [ContourPoint], index: Int, closed: Bool) -> ContourPoint {
    let count = points.count
    let previous: ContourPoint
    let next: ContourPoint
    if !closed && index == 0 {
        previous = points[0]
        next = points[1]
    } else if !closed && index == count - 1 {
        previous = points[count - 2]
        next = points[count - 1]
    } else {
        previous = points[(index - 1 + count) % count]
        next = points[(index + 1) % count]
    }
    let dx = next.x - previous.x
    let dy = next.y - previous.y
    let length = hypot(dx, dy)
    guard length > 1e-4 else { return ContourPoint(x: 0, y: 0) }
    return ContourPoint(x: -dy / length, y: dx / length)
}

private func extend(_ points: [ContourPoint], by extra: Float) -> [ContourPoint] {
    guard points.count >= 2 else { return points }
    var copy = points
    let start = points[0]
    let after = points[1]
    let startLength = hypot(start.x - after.x, start.y - after.y)
    if startLength > 1e-4 {
        copy[0] = ContourPoint(
            x: start.x + (start.x - after.x) / startLength * extra,
            y: start.y + (start.y - after.y) / startLength * extra
        )
    }
    let last = points.count - 1
    let end = points[last]
    let before = points[last - 1]
    let endLength = hypot(end.x - before.x, end.y - before.y)
    if endLength > 1e-4 {
        copy[last] = ContourPoint(
            x: end.x + (end.x - before.x) / endLength * extra,
            y: end.y + (end.y - before.y) / endLength * extra
        )
    }
    return copy
}

private func signedDistance(_ point: ContourPoint, guide: [ContourPoint], closed: Bool) -> Float {
    let (anchor, normal) = closestFrame(to: point, guide: guide, closed: closed)
    let dx = point.x - anchor.x
    let dy = point.y - anchor.y
    let sign: Float = dx * normal.x + dy * normal.y >= 0 ? 1 : -1
    return sign * hypot(dx, dy)
}

private func closestFrame(
    to point: ContourPoint,
    guide: [ContourPoint],
    closed: Bool
) -> (ContourPoint, ContourPoint) {
    let count = guide.count
    let segments = closed ? count : count - 1
    var best = Float.greatestFiniteMagnitude
    var anchor = guide[0]
    var normal = ContourPoint(x: 0, y: 1)
    for index in 0..<segments {
        let start = guide[index]
        let end = guide[(index + 1) % count]
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        var t: Float = 0
        if lengthSquared > 1e-6 {
            t = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        }
        let candidate = ContourPoint(x: start.x + dx * t, y: start.y + dy * t)
        let distance = hypot(point.x - candidate.x, point.y - candidate.y)
        if distance < best {
            best = distance
            anchor = candidate
            let length = sqrt(lengthSquared)
            if length > 1e-4 {
                normal = ContourPoint(x: -dy / length, y: dx / length)
            }
        }
    }
    return (anchor, normal)
}

// MARK: - Polygon

private func contains(_ point: ContourPoint, polygon: [ContourPoint]) -> Bool {
    var inside = false
    var previous = polygon.count - 1
    for index in 0..<polygon.count {
        let current = polygon[index]
        let prior = polygon[previous]
        if (current.y > point.y) != (prior.y > point.y) {
            let x = (prior.x - current.x) * (point.y - current.y) / (prior.y - current.y) + current.x
            if point.x < x {
                inside.toggle()
            }
        }
        previous = index
    }
    return inside
}

private func centroid(of polygon: [ContourPoint]) -> ContourPoint {
    var x: Float = 0
    var y: Float = 0
    for point in polygon {
        x += point.x
        y += point.y
    }
    let count = Float(polygon.count)
    return ContourPoint(x: x / count, y: y / count)
}

private func diagonal(of polygon: [ContourPoint]) -> Float {
    var minX = Float.greatestFiniteMagnitude
    var minY = Float.greatestFiniteMagnitude
    var maxX = -Float.greatestFiniteMagnitude
    var maxY = -Float.greatestFiniteMagnitude
    for point in polygon {
        minX = min(minX, point.x)
        minY = min(minY, point.y)
        maxX = max(maxX, point.x)
        maxY = max(maxY, point.y)
    }
    return hypot(maxX - minX, maxY - minY)
}

private func distanceToSegment(_ point: ContourPoint, _ a: ContourPoint, _ b: ContourPoint) -> Float {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 1e-6 else { return hypot(point.x - a.x, point.y - a.y) }
    let t = min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
    return hypot(point.x - (a.x + dx * t), point.y - (a.y + dy * t))
}

private func normalize(_ point: ContourPoint) -> ContourPoint {
    let length = hypot(point.x, point.y)
    guard length > 1e-5 else { return ContourPoint(x: 0, y: 1) }
    return ContourPoint(x: point.x / length, y: point.y / length)
}
