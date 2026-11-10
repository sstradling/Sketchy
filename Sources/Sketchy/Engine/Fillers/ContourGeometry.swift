//
//  ContourGeometry.swift
//  Sketchy
//
//  Clipped contour strokes before roughness is applied.
//
//  Each stroke is a full-width copy of the guide's bow, clipped to the polygon
//  with the even-odd rule. Intensity 0 is the straight chord. Intensity 1 keeps
//  the guide's bow. A lower intensity flattens that same wide bow (a larger
//  radius). It does not move the stroke onto a tighter concentric circle.
//  Graduation scales the bow along the stroke or from one stroke to the next.
//  Level sets stay ordered, so neighboring strokes do not cross.
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
            // Drop caps and corner stubs. A real stroke crosses most of the shape.
            let minChord = max(8, scan.across * 0.35)
            let pieces = scan.pieces(at: offset, polygon: polygon)
            for piece in pieces {
                guard chord(piece) >= minChord else { continue }
                strokes.append(ContourStroke(
                    slot: placement.slot,
                    offset: offset,
                    scale: scale,
                    points: piece
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
    /// Width of the shape across the strokes. Short clips under about a third of this are stubs.
    var across: Float
    var clip: (Float, [ContourPoint]) -> [[ContourPoint]]

    init(
        travel: ContourPoint,
        range: ScanRange,
        across: Float,
        clip: @escaping (Float, [ContourPoint]) -> [[ContourPoint]]
    ) {
        self.travel = travel
        self.range = range
        self.across = across
        self.clip = clip
    }

    init?(polygon: [ContourPoint], options: Options) {
        switch options.contourGuide {
        case let .arc(center, radius):
            guard let scan = Scan.arc(
                center: center, guideRadius: radius, polygon: polygon, options: options
            ) else { return nil }
            self = scan
        case let .polyline(points, closed):
            guard points.count >= 2,
                  let scan = Scan.polyline(
                    points: points, closed: closed, polygon: polygon, options: options
                  ) else {
                return nil
            }
            self = scan
        case nil:
            guard let scan = Scan.lines(angle: options.fillAngle, polygon: polygon, options: options) else {
                return nil
            }
            self = scan
        }
    }

    func pieces(at offset: Float, polygon: [ContourPoint]) -> [[ContourPoint]] {
        clip(offset, polygon)
    }

    static func arc(
        center: ContourPoint,
        guideRadius: Float,
        polygon: [ContourPoint],
        options: Options
    ) -> Scan? {
        guard guideRadius > 1 else { return nil }
        let centroid = centroid(of: polygon)
        var toward = ContourPoint(x: centroid.x - center.x, y: centroid.y - center.y)
        toward = normalize(toward)
        let guidePoint = ContourPoint(
            x: center.x + toward.x * guideRadius,
            y: center.y + toward.y * guideRadius
        )
        var into = ContourPoint(x: centroid.x - guidePoint.x, y: centroid.y - guidePoint.y)
        if hypot(into.x, into.y) < 1 {
            into = ContourPoint(x: -toward.x, y: -toward.y)
        }
        let travel = normalize(into)
        let tangent = ContourPoint(x: travel.y, y: -travel.x)
        let frame = BowFrame(origin: guidePoint, travel: travel, tangent: tangent)
        let centerU = frame.u(of: center)
        let centerS = frame.s(of: center)
        let sigma: Float = centerS >= 0 ? 1 : -1
        let guideS: (Float) -> Float = { u in
            arcDepth(u - centerU, radius: guideRadius, centerS: centerS, sigma: sigma)
        }
        return makeScan(frame: frame, guideS: guideS, polygon: polygon, options: options)
    }

    static func lines(angle: Float, polygon: [ContourPoint], options: Options) -> Scan? {
        let radians = angle * Float.pi / 180
        let tangent = ContourPoint(x: cos(radians), y: sin(radians))
        let travel = ContourPoint(x: -tangent.y, y: tangent.x)
        let frame = BowFrame(origin: centroid(of: polygon), travel: travel, tangent: tangent)
        return makeScan(frame: frame, guideS: { _ in 0 }, polygon: polygon, options: options)
    }

    static func polyline(
        points: [ContourPoint],
        closed: Bool,
        polygon: [ContourPoint],
        options: Options
    ) -> Scan? {
        let centroid = centroid(of: polygon)
        let (anchor, normal) = closestFrame(to: centroid, guide: points, closed: closed)
        var travel = normal
        let into = ContourPoint(x: centroid.x - anchor.x, y: centroid.y - anchor.y)
        if into.x * normal.x + into.y * normal.y < 0 {
            travel = ContourPoint(x: -normal.x, y: -normal.y)
        }
        travel = normalize(travel)
        let tangent = ContourPoint(x: travel.y, y: -travel.x)
        let frame = BowFrame(origin: anchor, travel: travel, tangent: tangent)
        let samples = points.map { (frame.u(of: $0), frame.s(of: $0)) }.sorted { $0.0 < $1.0 }
        guard samples.count >= 2 else { return nil }
        let guideS: (Float) -> Float = { u in
            interpolate(samples, at: u)
        }
        return makeScan(frame: frame, guideS: guideS, polygon: polygon, options: options)
    }

    private static func makeScan(
        frame: BowFrame,
        guideS: @escaping (Float) -> Float,
        polygon: [ContourPoint],
        options: Options
    ) -> Scan? {
        let us = polygon.map { frame.u(of: $0) }
        let ss = polygon.map { frame.s(of: $0) }
        guard let uMin = us.min(), let uMax = us.max(), uMax - uMin > 1 else { return nil }
        guard let sMin = ss.min(), let sMax = ss.max(), sMax - sMin > 0.5 else { return nil }
        let crest = guideS((uMin + uMax) / 2)
        let guideAtLow = abs(sMin - crest) <= abs(sMax - crest)
        let bow = bowDeviation(guideS: guideS, uMin: uMin, uMax: uMax)
        let field = IntensityField(polygon: polygon, options: options)
        let range = ScanRange(low: sMin, high: sMax, guideAtLow: guideAtLow)
        return Scan(travel: frame.travel, range: range, across: uMax - uMin) { offset, polygon in
            widePieces(
                s0: offset,
                frame: frame,
                uMin: uMin,
                uMax: uMax,
                bow: bow,
                field: field,
                polygon: polygon
            )
        }
    }
}

// MARK: - Wide bow

private struct BowFrame {
    var origin: ContourPoint
    var travel: ContourPoint
    var tangent: ContourPoint

    func u(of point: ContourPoint) -> Float {
        (point.x - origin.x) * tangent.x + (point.y - origin.y) * tangent.y
    }

    func s(of point: ContourPoint) -> Float {
        (point.x - origin.x) * travel.x + (point.y - origin.y) * travel.y
    }

    func point(u: Float, s: Float) -> ContourPoint {
        ContourPoint(
            x: origin.x + tangent.x * u + travel.x * s,
            y: origin.y + tangent.y * u + travel.y * s
        )
    }
}

/// Depth of a circular guide along `travel`. The crest (`u == 0` in center space) sits at `s == 0`.
private func arcDepth(_ du: Float, radius: Float, centerS: Float, sigma: Float) -> Float {
    let limit = radius * 0.995
    if abs(du) <= limit {
        return centerS - sigma * sqrt(max(0, radius * radius - du * du))
    }
    let edge = limit * (du < 0 ? -1 : 1)
    let edgeS = centerS - sigma * sqrt(max(0, radius * radius - edge * edge))
    let slope = sigma * edge / sqrt(max(0.01, radius * radius - edge * edge))
    return edgeS + slope * (du - edge)
}

/// Guide depth minus the straight chord across `[uMin, uMax]`. Zero at both ends.
private func bowDeviation(
    guideS: @escaping (Float) -> Float,
    uMin: Float,
    uMax: Float
) -> (Float) -> Float {
    let span = max(uMax - uMin, 0.001)
    let start = guideS(uMin)
    let end = guideS(uMax)
    return { u in
        let clamped = min(uMax, max(uMin, u))
        let t = (clamped - uMin) / span
        return guideS(clamped) - (start + (end - start) * t)
    }
}

private func interpolate(_ samples: [(Float, Float)], at u: Float) -> Float {
    guard let first = samples.first else { return 0 }
    if u <= first.0 { return first.1 }
    guard let last = samples.last else { return 0 }
    if u >= last.0 { return last.1 }
    for index in 1..<samples.count {
        let left = samples[index - 1]
        let right = samples[index]
        if u <= right.0 {
            let span = max(right.0 - left.0, 0.001)
            let t = (u - left.0) / span
            return left.1 + (right.1 - left.1) * t
        }
    }
    return last.1
}

/// One full-width bow at scan depth `s0`, clipped to the polygon.
///
/// The unbowed line sits at `s0`. Intensity scales the guide's bow and is read
/// on that line, so a horizontal ramp is the same shape on every stroke and a
/// vertical ramp only changes from one stroke to the next. Either way the
/// curves stay in order.
private func widePieces(
    s0: Float,
    frame: BowFrame,
    uMin: Float,
    uMax: Float,
    bow: (Float) -> Float,
    field: IntensityField,
    polygon: [ContourPoint]
) -> [[ContourPoint]] {
    let span = max(uMax - uMin, 1)
    let steps = min(48, max(16, Int(span / 10)))
    let pad = span * 0.08 + 4
    var chain: [ContourPoint] = []
    chain.reserveCapacity(steps + 1)
    for step in 0...steps {
        let u = (uMin - pad) + (span + pad * 2) * Float(step) / Float(steps)
        let clamped = min(uMax, max(uMin, u))
        let k = field.value(at: frame.point(u: clamped, s: s0))
        let depth = s0 + k * bow(clamped)
        chain.append(frame.point(u: u, s: depth))
    }
    return clipChain(chain, closed: false, polygon: polygon)
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

private func normalize(_ point: ContourPoint) -> ContourPoint {
    let length = hypot(point.x, point.y)
    guard length > 1e-5 else { return ContourPoint(x: 0, y: 1) }
    return ContourPoint(x: point.x / length, y: point.y / length)
}
