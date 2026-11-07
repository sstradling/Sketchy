//
//  SketchGroup.swift
//  Sketchy
//
//  Several RoughView drawings that share one sticker sheet.
//
//  Route: SketchGroup.body draws the backing first, then each part in order.
//  Child SVG paths stay in their authored coordinates. sketchTransform and
//  the part transforms move them. SwiftUI does not supply .offset or
//  .scaleEffect back to this group, so those are not part of the silhouette.
//

import SwiftUI
import UIKit

/// One drawing inside a `SketchGroup`, plus a transform in the group's coordinates.
public struct SketchPart {
    public var content: RoughView
    var transform: CGAffineTransform

    public init(_ content: RoughView) {
        self.content = content
        self.transform = .identity
    }

    /// Moves the part. The offset is in the group's coordinate space, before `SketchGroup.sketchTransform`.
    public func sketchOffset(x: CGFloat = 0, y: CGFloat = 0) -> SketchPart {
        applying(CGAffineTransform(translationX: x, y: y))
    }

    /// Scales the part around `anchor`. Stroke widths stay in points.
    public func sketchScale(_ scale: CGFloat, around anchor: CGPoint = .zero) -> SketchPart {
        let shift = CGAffineTransform(translationX: anchor.x, y: anchor.y)
        let back = CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
        return applying(back.concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(shift))
    }

    /// Rotates the part around `anchor`.
    public func sketchRotation(_ angle: Angle, around anchor: CGPoint = .zero) -> SketchPart {
        let shift = CGAffineTransform(translationX: anchor.x, y: anchor.y)
        let back = CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
        let radians = CGFloat(angle.radians)
        return applying(back.concatenating(CGAffineTransform(rotationAngle: radians)).concatenating(shift))
    }

    /// Appends a transform. Later transforms apply after earlier ones.
    public func sketchTransform(_ transform: CGAffineTransform) -> SketchPart {
        applying(transform)
    }

    private func applying(_ next: CGAffineTransform) -> SketchPart {
        var copy = self
        copy.transform = transform.concatenating(next)
        return copy
    }
}

@resultBuilder
public enum SketchPartBuilder {
    public static func buildExpression(_ view: RoughView) -> [SketchPart] {
        [SketchPart(view)]
    }

    public static func buildExpression(_ part: SketchPart) -> [SketchPart] {
        [part]
    }

    public static func buildExpression(_ parts: [SketchPart]) -> [SketchPart] {
        parts
    }

    public static func buildBlock(_ parts: [SketchPart]...) -> [SketchPart] {
        parts.flatMap { $0 }
    }

    public static func buildOptional(_ part: [SketchPart]?) -> [SketchPart] {
        part ?? []
    }

    public static func buildEither(first: [SketchPart]) -> [SketchPart] { first }
    public static func buildEither(second: [SketchPart]) -> [SketchPart] { second }

    public static func buildArray(_ parts: [[SketchPart]]) -> [SketchPart] {
        parts.flatMap { $0 }
    }
}

/// Drawings that share one paper cutout.
///
/// This is not a group of arbitrary SwiftUI views. Each child is a `RoughView`
/// or a `SketchPart`. Their outlines are combined in vector space, then one
/// `StickerBacking` is drawn behind the stack. A part's own `.stickerBacking`
/// is ignored while the group has one, so internal edges do not grow halos.
///
/// Child SVG paths are not fitted one-by-one into the view. They keep the
/// coordinates you wrote. Use `sketchTransform` for a shared scale or move.
/// SwiftUI `.offset`, `.scaleEffect`, and `.rotationEffect` on a child are
/// not visible to the silhouette.
public struct SketchGroup: View {
    var parts: [SketchPart]
    var backing: StickerBacking?
    var transform: CGAffineTransform
    var seed: UInt64?

    public init(@SketchPartBuilder content: () -> [SketchPart]) {
        self.parts = content()
        self.backing = nil
        self.transform = .identity
        self.seed = nil
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { context, canvasSize in
                let renderSize = canvasSize == .zero ? size : canvasSize
                guard renderSize.width > 0, renderSize.height > 0 else { return }
                SketchGroupRenderer.draw(
                    parts: parts,
                    backing: backing,
                    groupTransform: transform,
                    seed: seed,
                    in: &context,
                    size: renderSize
                )
            }
        }
    }

    /// One sheet behind every part. Pass nil to draw the parts with no shared paper.
    public func stickerBacking(_ backing: StickerBacking?) -> SketchGroup {
        var copy = self
        copy.backing = backing
        return copy
    }

    /// Shared paper. See `StickerBacking`.
    public func stickerBacking(
        width: CGFloat,
        smoothness: CGFloat = 0,
        edge: StickerEdge = .smooth,
        color: Color = .white,
        texture: StickerTexture? = nil,
        shadow: StickerShadow? = nil
    ) -> SketchGroup {
        stickerBacking(StickerBacking(
            width: width,
            smoothness: smoothness,
            edge: edge,
            color: UIColor(color),
            texture: texture,
            shadow: shadow
        ))
    }

    /// Shared paper in a `UIColor`. `color` is required so `.white` is not ambiguous.
    public func stickerBacking(
        width: CGFloat,
        smoothness: CGFloat = 0,
        edge: StickerEdge = .smooth,
        color: UIColor,
        texture: StickerTexture? = nil,
        shadow: StickerShadow? = nil
    ) -> SketchGroup {
        stickerBacking(StickerBacking(
            width: width,
            smoothness: smoothness,
            edge: edge,
            color: color,
            texture: texture,
            shadow: shadow
        ))
    }

    /// Seed for the torn edge. Nil uses the first part's `Options.seed`, then a fixed seed.
    public func seed(_ value: UInt64) -> SketchGroup {
        var copy = self
        copy.seed = value
        return copy
    }

    /// Moves and scales the whole composition, including the sheet.
    ///
    /// Stroke widths, the backing width, and a sticker shadow's offset and
    /// blur stay in points. They are not multiplied by the scale.
    public func sketchTransform(_ transform: CGAffineTransform) -> SketchGroup {
        var copy = self
        copy.transform = self.transform.concatenating(transform)
        return copy
    }
}

@MainActor
enum SketchGroupRenderer {
    private static let renderer = SwiftUIRenderer()

    /// The merged silhouette, before the backing width is applied. Tests use this.
    static func silhouetteLines(
        parts: [SketchPart],
        backing: StickerBacking,
        groupTransform: CGAffineTransform = .identity,
        size: CGSize
    ) -> [StickerBackingBuilder.Centerline] {
        silhouette(
            parts: parts,
            backing: backing,
            groupTransform: groupTransform,
            generator: Engine.shared.generator(size: size),
            size: size
        )
    }

    static func draw(
        parts: [SketchPart],
        backing: StickerBacking?,
        groupTransform: CGAffineTransform,
        seed: UInt64?,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let generator = Engine.shared.generator(size: size)
        if let backing, backing.width > 0 {
            let lines = silhouette(
                parts: parts,
                backing: backing,
                groupTransform: groupTransform,
                generator: generator,
                size: size
            )
            let tearSeed = seed ?? parts.first?.content.options.seed
            let sheet = StickerBackingBuilder.commands(
                for: lines,
                outward: backing.width,
                backing: backing,
                seed: tearSeed
            )
            renderer.render(commands: sheet, in: &context)
        }
        for part in parts {
            let placement = part.transform.concatenating(groupTransform)
            var options = part.content.options
            if backing?.width ?? 0 > 0 {
                options.stickerBacking = nil
            }
            for drawable in part.content.drawables {
                guard let drawing = generator.generate(drawable: drawable, options: options) else { continue }
                let commands = renderer.commands(
                    for: drawing,
                    options: options,
                    in: size,
                    placement: placement,
                    fitsSVG: false
                )
                renderer.render(commands: commands, in: &context)
            }
        }
    }

    /// Ink hulls, half a stroke outside each centerline, merged where they overlap.
    private static func silhouette(
        parts: [SketchPart],
        backing: StickerBacking,
        groupTransform: CGAffineTransform,
        generator: NativeGenerator,
        size: CGSize
    ) -> [StickerBackingBuilder.Centerline] {
        var rings: [SilhouetteRing] = []
        var shapeID = 0
        for part in parts {
            guard contributes(part.content.options) else { continue }
            let placement = part.transform.concatenating(groupTransform)
            var options = part.content.options
            options.stickerBacking = backing
            for drawable in part.content.drawables {
                guard let drawing = generator.generate(drawable: drawable, options: options) else { continue }
                let transform = drawing.shape == "path" ? placement : nil
                let lines = StickerBackingBuilder.centerlines(
                    for: drawing,
                    options: options,
                    backing: backing,
                    transform: transform
                )
                let placed = lines.map { line -> StickerBackingBuilder.Centerline in
                    guard drawing.shape != "path" else { return line }
                    return StickerBackingBuilder.Centerline(
                        points: line.points.map { $0.applying(placement) },
                        closed: line.closed,
                        source: line.source.map { $0.applying(placement) }
                    )
                }
                let stroke = max(0, CGFloat(
                    drawing.shape == "path" ? options.effectiveSVGStrokeWidth : options.strokeWidth
                ))
                let closed = placed.filter { $0.closed && $0.points.count >= 3 }
                for (index, line) in closed.enumerated() {
                    let hole = nesting(index, in: closed)
                    let distance = hole ? -stroke / 2 : stroke / 2
                    let hull = abs(distance) > 0.4
                        ? (StickerBackingBuilder.offsetClosed(line.points, by: distance) ?? line.points)
                        : line.points
                    rings.append(SilhouetteRing(points: hull, shape: shapeID, isHole: hole))
                }
                if stroke > 0.4 {
                    for line in placed where !line.closed && line.points.count >= 2 {
                        for loop in strokeLoops(line.points, width: stroke, options: options) {
                            rings.append(SilhouetteRing(points: loop, shape: shapeID, isHole: false))
                        }
                    }
                }
                shapeID += 1
            }
        }
        let combined = SilhouetteUnion.combine(rings)
        let simplifyTorn = if case .torn = backing.edge { true } else { false }
        return combined.map { ring in
            let points = simplifyTorn ? simplify(ring.points, epsilon: 1.8) : ring.points
            return StickerBackingBuilder.Centerline(points: points, closed: true, source: ring.points)
        }
    }

    /// Drops points that sit on a straight run so a torn edge can cut facets
    /// without the dense union immediately crossing itself.
    private static func simplify(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 8 else { return points }
        return rdp(points, epsilon: epsilon, closed: true)
    }

    private static func rdp(_ points: [CGPoint], epsilon: CGFloat, closed: Bool) -> [CGPoint] {
        func recurse(_ input: [CGPoint]) -> [CGPoint] {
            guard input.count > 2 else { return input }
            let start = input[0]
            let end = input[input.count - 1]
            var farthest = 0
            var distance: CGFloat = 0
            let span = hypot(end.x - start.x, end.y - start.y)
            for index in 1..<(input.count - 1) {
                let point = input[index]
                let deviation: CGFloat
                if span < 1e-4 {
                    deviation = hypot(point.x - start.x, point.y - start.y)
                } else {
                    deviation = abs(
                        (end.y - start.y) * point.x
                        - (end.x - start.x) * point.y
                        + end.x * start.y
                        - end.y * start.x
                    ) / span
                }
                if deviation > distance {
                    distance = deviation
                    farthest = index
                }
            }
            guard distance > epsilon else { return [start, end] }
            let left = recurse(Array(input[0...farthest]))
            let right = recurse(Array(input[farthest...]))
            return left.dropLast() + right
        }
        var ring = points
        if closed, let first = ring.first {
            ring.append(first)
        }
        let reduced = recurse(ring)
        var open = reduced
        if closed, open.count >= 2, hypot(open[0].x - open[open.count - 1].x, open[0].y - open[open.count - 1].y) < 0.5 {
            open.removeLast()
        }
        return open.count >= 8 ? open : points
    }

    private static func contributes(_ options: Options) -> Bool {
        let fill = options.fill.cgColor.alpha * CGFloat(options.fillOpacity)
        let stroke = options.stroke.cgColor.alpha * CGFloat(options.strokeOpacity)
        return fill > 0.02 || stroke > 0.02
    }

    /// The filled outline of an open stroke, already the ink hull.
    private static func strokeLoops(_ points: [CGPoint], width: CGFloat, options: Options) -> [[CGPoint]] {
        var path = SwiftUI.Path()
        guard let first = points.first else { return [] }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        let outline = NativeStrokeOutline.path(
            from: path,
            width: width,
            cap: options.strokeCap,
            join: options.strokeJoin,
            miterLimit: options.strokeMiterLimit
        )
        var loops: [[CGPoint]] = []
        var current: [CGPoint] = []
        outline.cgPath.applyWithBlock { element in
            let samples = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                if current.count >= 3 { loops.append(current) }
                current = [samples[0]]
            case .addLineToPoint:
                current.append(samples[0])
            case .addQuadCurveToPoint:
                current.append(samples[1])
            case .addCurveToPoint:
                current.append(samples[2])
            case .closeSubpath:
                if current.count >= 3 { loops.append(current) }
                current = []
            @unknown default:
                break
            }
        }
        if current.count >= 3 { loops.append(current) }
        return loops
    }

    /// Odd containment means a hole, matching the single-shape sheet.
    private static func nesting(_ index: Int, in lines: [StickerBackingBuilder.Centerline]) -> Bool {
        let sample = centroid(lines[index].points)
        let area = abs(signedArea(lines[index].points))
        var depth = 0
        for other in lines.indices where other != index {
            guard abs(signedArea(lines[other].points)) > area * 1.02 else { continue }
            if contains(sample, lines[other].points) { depth += 1 }
        }
        return !depth.isMultiple(of: 2)
    }

    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let count = CGFloat(max(points.count, 1))
        return CGPoint(x: sum.x / count, y: sum.y / count)
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

    private static func contains(_ point: CGPoint, _ ring: [CGPoint]) -> Bool {
        var inside = false
        var previous = ring.count - 1
        for index in ring.indices {
            let currentY = ring[index].y
            let previousY = ring[previous].y
            if (currentY > point.y) != (previousY > point.y) {
                let x = (ring[previous].x - ring[index].x) * (point.y - currentY)
                    / (previousY - currentY) + ring[index].x
                if point.x < x { inside.toggle() }
            }
            previous = index
        }
        return inside
    }
}
