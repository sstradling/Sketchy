//
//  ContourGuide.swift
//  Sketchy
//
//  Guide curve, curvature, and drift for the contour fill.
//

import CoreGraphics
import Foundation

/// A point in the same coordinate space as a shape.
///
/// Core Graphics y points down. `ContourGuide` and the filled shape share these units.
public struct ContourPoint: Equatable, Hashable, Sendable {
    public var x: Float
    public var y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.x = Float(point.x)
        self.y = Float(point.y)
    }
}

/// Curve the contour fill follows.
///
/// The guide is independent of the filled shape. A lake can use the same arc
/// as the ground and clip the strokes to the lake. Coordinates match the
/// shape: a `Polygon` or `Rectangle` uses its own points, and an SVG `Path`
/// uses the path's coordinates before the view fits it.
public enum ContourGuide: Equatable, Hashable, Sendable {
    /// Circular guide. `radius` is the reference curve, such as a horizon.
    /// Strokes are offset along the radius and clipped to the shape.
    case arc(center: ContourPoint, radius: Float)

    /// Guide polyline in shape coordinates. Strokes are offset along its normals.
    case polyline(points: [ContourPoint], closed: Bool)

    /// Circular guide from a Core Graphics center and radius.
    public static func arc(center: CGPoint, radius: CGFloat) -> ContourGuide {
        .arc(
            center: ContourPoint(x: Float(center.x), y: Float(center.y)),
            radius: Float(radius)
        )
    }

    /// Flattens `path` into a polyline guide.
    ///
    /// Curves are sampled. A later `moveTo` starts a new subpath and is ignored;
    /// a guide is one curve. `flatness` is the sample spacing in points.
    public static func path(_ path: CGPath, flatness: Float = 2) -> ContourGuide {
        let walker = PathWalker(flatness: max(0.5, flatness))
        path.applyWithBlock { element in
            walker.consume(element.pointee)
        }
        return .polyline(points: walker.points, closed: walker.closed)
    }
}

/// How contour intensity moves from the start of the gradient to the end.
public enum ContourEasing: String, Equatable, Hashable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    /// Maps `t` in `0...1` through the easing curve.
    public func value(_ t: Float) -> Float {
        let t = min(1, max(0, t))
        switch self {
        case .linear:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            let u = 1 - t
            return 1 - u * u
        case .easeInOut:
            return t * t * (3 - 2 * t)
        }
    }
}

/// Scrolls a contour fill along `angle` without re-rolling its wobble.
///
/// `speed` is points per second along `angle`. `phase` is the distance already
/// traveled, in points. The filler keeps the component of that motion along
/// the guide's offset axis and wraps it so the stroke field repeats.
/// Each stroke keeps the roughness seed of its slot, so a frame does not boil.
public struct ContourDrift: Equatable, Hashable, Sendable {
    public var speed: Float
    public var angle: Float
    public var phase: Float

    public init(speed: Float, angle: Float, phase: Float = 0) {
        self.speed = speed
        self.angle = angle
        self.phase = phase
    }
}

/// One slot of the repeating contour field.
struct ContourPlacement: Equatable {
    var slot: Int
    var u: Float
}

/// Placement of a seeded contour field.
///
/// Slots are a fixed lattice. `phaseSlots` slides the lattice and wraps at
/// `count`, so the same slot comes back to the same place after one period.
/// `falloff` packs slots toward `u == 0` (the guide side). `u` is `0` at the
/// guide and `1` at the far side.
enum ContourField {
    static func placements(count: Int, falloff: Float, phaseSlots: Float) -> [ContourPlacement] {
        let count = max(count, 1)
        let exponent = 1 + min(1, max(0, falloff))
        return (0..<count).map { slot in
            let raw = (Float(slot) + phaseSlots) / Float(count)
            let wrapped = raw - floor(raw)
            return ContourPlacement(slot: slot, u: pow(wrapped, exponent))
        }
    }

    /// Mixes a drawing seed with a slot so each stroke keeps its own sequence.
    static func mix(_ seed: UInt64, _ slot: Int) -> UInt64 {
        var x = seed &+ 0x9E3779B97F4A7C15
        x ^= UInt64(bitPattern: Int64(slot)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        return x ^ (x >> 31)
    }
}

private final class PathWalker {
    let flatness: Float
    var points: [ContourPoint] = []
    var closed = false
    private var cursor = ContourPoint(x: 0, y: 0)
    private var stopped = false

    init(flatness: Float) {
        self.flatness = flatness
    }

    func consume(_ element: CGPathElement) {
        guard !stopped else { return }
        switch element.type {
        case .moveToPoint:
            if !points.isEmpty {
                stopped = true
                return
            }
            cursor = ContourPoint(element.points[0])
            points.append(cursor)
        case .addLineToPoint:
            cursor = ContourPoint(element.points[0])
            points.append(cursor)
        case .addQuadCurveToPoint:
            let control = element.points[0]
            let end = element.points[1]
            sample(from: cursor, control: control, to: end)
            cursor = ContourPoint(end)
        case .addCurveToPoint:
            let c1 = element.points[0]
            let c2 = element.points[1]
            let end = element.points[2]
            sample(from: cursor, c1: c1, c2: c2, to: end)
            cursor = ContourPoint(end)
        case .closeSubpath:
            closed = true
        @unknown default:
            break
        }
    }

    private func sample(from start: ContourPoint, control: CGPoint, to end: CGPoint) {
        let steps = sampleCount(from: start, to: ContourPoint(end))
        for step in 1...steps {
            let t = Float(step) / Float(steps)
            let u = 1 - t
            let c = ContourPoint(control)
            let p = ContourPoint(end)
            points.append(ContourPoint(
                x: u * u * start.x + 2 * u * t * c.x + t * t * p.x,
                y: u * u * start.y + 2 * u * t * c.y + t * t * p.y
            ))
        }
    }

    private func sample(from start: ContourPoint, c1: CGPoint, c2: CGPoint, to end: CGPoint) {
        let steps = sampleCount(from: start, to: ContourPoint(end))
        let p1 = ContourPoint(c1)
        let p2 = ContourPoint(c2)
        let p3 = ContourPoint(end)
        for step in 1...steps {
            let t = Float(step) / Float(steps)
            let u = 1 - t
            let uu = u * u
            let tt = t * t
            points.append(ContourPoint(
                x: uu * u * start.x + 3 * uu * t * p1.x + 3 * u * tt * p2.x + tt * t * p3.x,
                y: uu * u * start.y + 3 * uu * t * p1.y + 3 * u * tt * p2.y + tt * t * p3.y
            ))
        }
    }

    private func sampleCount(from start: ContourPoint, to end: ContourPoint) -> Int {
        let length = hypot(end.x - start.x, end.y - start.y)
        return min(24, max(4, Int(ceil(length / flatness))))
    }
}
