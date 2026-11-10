//
//  WashStroke.swift
//  Sketchy
//
//  Shared crayon-wash stroke recipe used by the sky wash and, optionally, contour fills.
//
//  A pass walks across a region. Each stroke gets its own angle scatter, width,
//  opacity, end trim, and a small sine bow, then the same rough centerline the
//  other fills use. The numbers on `WashPass.sky` match the SlapDuck sky recipe
//  in canvas pixels. Scale them for a smaller view.
//

import Foundation

/// One band of a crayon wash.
///
/// Lengths are points. `WashPass.sky` is the two-pass sky from the mockups
/// (widths about 42–58 and 28–42, trims 28 and 48). Call `scaled(by:)` when
/// the view is smaller than that canvas.
public struct WashPass: Equatable, Hashable, Sendable {
    public var spacingMin: Float
    public var spacingSpan: Float
    public var widthMin: Float
    public var widthSpan: Float
    public var opacityMin: Float
    public var opacitySpan: Float
    public var trimMax: Float
    /// Extra degrees of angle scatter around `fillAngle`.
    public var angleSpread: Float
    /// Peak of the sine bow, in points. The stroke also adds a smaller second harmonic.
    public var bow: Float
    /// Drop a stroke shorter than this after trimming.
    public var minLength: Float
    public var roughness: Float
    public var bowing: Float
    public var randomness: Float
    /// Mixed into `Options.seed` so the two sky passes do not share a sequence.
    public var seed: UInt64

    public init(
        spacingMin: Float,
        spacingSpan: Float,
        widthMin: Float,
        widthSpan: Float,
        opacityMin: Float,
        opacitySpan: Float,
        trimMax: Float,
        angleSpread: Float,
        bow: Float = 18,
        minLength: Float = 24,
        roughness: Float = 2.1,
        bowing: Float = 1.8,
        randomness: Float = 2.6,
        seed: UInt64
    ) {
        self.spacingMin = spacingMin
        self.spacingSpan = spacingSpan
        self.widthMin = widthMin
        self.widthSpan = widthSpan
        self.opacityMin = opacityMin
        self.opacitySpan = opacitySpan
        self.trimMax = trimMax
        self.angleSpread = angleSpread
        self.bow = bow
        self.minLength = minLength
        self.roughness = roughness
        self.bowing = bowing
        self.randomness = randomness
        self.seed = seed
    }

    /// Two sky passes. Widths, gaps, and trims are the mockup's canvas pixels.
    public static let sky: [WashPass] = [
        WashPass(
            spacingMin: 22, spacingSpan: 8,
            widthMin: 42, widthSpan: 16,
            opacityMin: 0.16, opacitySpan: 0.08,
            trimMax: 28, angleSpread: 7, seed: 1400
        ),
        WashPass(
            spacingMin: 34, spacingSpan: 14,
            widthMin: 28, widthSpan: 14,
            opacityMin: 0.10, opacitySpan: 0.06,
            trimMax: 48, angleSpread: 16, seed: 2600
        )
    ]

    /// Scales spacing, width, trim, bow, and the minimum length. Angle and seeds stay put.
    public func scaled(by factor: Float) -> WashPass {
        let factor = max(0.05, factor)
        var copy = self
        copy.spacingMin *= factor
        copy.spacingSpan *= factor
        copy.widthMin *= factor
        copy.widthSpan *= factor
        copy.trimMax *= factor
        copy.bow *= factor
        copy.minLength *= factor
        return copy
    }

    public static func sky(scale: Float) -> [WashPass] {
        sky.map { $0.scaled(by: scale) }
    }
}

/// Turns one centerline into the rough stroke used by a wash pass.
enum WashStrokeBuilder {
    static func operations(
        points: [[Float]],
        seed: UInt64,
        pass: WashPass
    ) -> [Operation] {
        guard points.count >= 2 else { return [] }
        var options = Options()
        options.seed = seed
        options.roughness = pass.roughness
        options.bowing = pass.bowing
        options.maxRandomnessOffset = pass.randomness
        return RoughRandom.isolated(seed: seed) {
            RoughMath.curveOps(points: points, options: options)
        }
    }

    /// Trims both ends, then lays a sine bow along the normal.
    ///
    /// `bow` is the peak displacement in points. `0` leaves the centerline shape alone.
    static func shape(
        _ points: [ContourPoint],
        trimStart: Float,
        trimEnd: Float,
        bow: Float
    ) -> [[Float]] {
        let trimmed = trim(points, start: trimStart, end: trimEnd)
        guard trimmed.count >= 2 else { return [] }
        guard abs(bow) > 0.01 else {
            return trimmed.map { [$0.x, $0.y] }
        }
        let count = trimmed.count
        return trimmed.enumerated().map { index, point in
            let t = Float(index) / Float(max(count - 1, 1))
            let side = sin(t * .pi) * bow + sin(t * .pi * 2) * bow * 0.35
            let normal = normalAt(trimmed, index: index)
            return [point.x + normal.x * side, point.y + normal.y * side]
        }
    }

    static func trim(_ points: [ContourPoint], start: Float, end: Float) -> [ContourPoint] {
        guard points.count >= 2 else { return [] }
        let total = length(points)
        let cutStart = min(max(0, start), total * 0.45)
        let cutEnd = min(max(0, end), total * 0.45)
        if total - cutStart - cutEnd < 1 { return [] }
        var kept: [ContourPoint] = []
        var traveled: Float = 0
        for index in 1..<points.count {
            let a = points[index - 1]
            let b = points[index]
            let span = hypot(b.x - a.x, b.y - a.y)
            let next = traveled + span
            if next >= cutStart && traveled <= total - cutEnd {
                if kept.isEmpty {
                    let t = span > 0.001 ? min(1, max(0, (cutStart - traveled) / span)) : 0
                    kept.append(ContourPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                }
                if next <= total - cutEnd {
                    kept.append(b)
                } else {
                    let t = span > 0.001 ? min(1, max(0, (total - cutEnd - traveled) / span)) : 1
                    kept.append(ContourPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                    break
                }
            }
            traveled = next
        }
        return kept
    }

    private static func length(_ points: [ContourPoint]) -> Float {
        var total: Float = 0
        for index in 1..<points.count {
            total += hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
        }
        return total
    }

    private static func normalAt(_ points: [ContourPoint], index: Int) -> ContourPoint {
        let previous = points[max(0, index - 1)]
        let next = points[min(points.count - 1, index + 1)]
        let dx = next.x - previous.x
        let dy = next.y - previous.y
        let span = hypot(dx, dy)
        guard span > 1e-4 else { return ContourPoint(x: 0, y: -1) }
        return ContourPoint(x: -dy / span, y: dx / span)
    }
}

struct WashRandom {
    var generator: SplitMix64

    init(seed: UInt64) {
        generator = SplitMix64(seed: seed)
    }

    mutating func unit() -> Float {
        Float.random(in: 0...1, using: &generator)
    }
}
