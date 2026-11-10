//
//  InteriorShadePainter.swift
//  Sketchy
//
//  Draws InteriorShade into a GraphicsContext.
//
//  SwiftUIRenderer.commands builds one command per shade from the input
//  silhouette (not the rough outline). renderCommand calls draw. An inner
//  shadow is the exterior shape, blurred and offset, then clipped to the
//  interior. Gradients clip the same way. A halo is the outside half of a
//  stroke, blurred after that clip so the glow can fall back onto the shape.
//

import CoreGraphics
import SwiftUI
import UIKit

enum InteriorShadePainter {

    static func path(
        guides: [StickerGuideRing]?,
        shape: String,
        transform: CGAffineTransform?
    ) -> SwiftUI.Path? {
        guard let guides else { return nil }
        let rings = guides.filter(\.closed).map { ring -> StickerGuideRing in
            guard let transform else { return ring }
            return StickerGuideRing(
                points: ring.points.map { $0.applying(transform) },
                closed: true
            )
        }.filter { $0.points.count >= 3 }
        guard !rings.isEmpty else { return nil }

        if (shape == "circle" || shape == "ellipse"), rings.count == 1 {
            return SwiftUI.Path(ellipseIn: bounds(of: rings[0].points))
        }

        var path = SwiftUI.Path()
        for ring in rings {
            guard let first = ring.points.first else { continue }
            path.move(to: first)
            for point in ring.points.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }
        return path
    }

    static func commands(
        path: SwiftUI.Path,
        shades: [InteriorShade]
    ) -> (beforeStroke: [RoughRenderCommand], afterStroke: [RoughRenderCommand]) {
        var before: [RoughRenderCommand] = []
        var after: [RoughRenderCommand] = []
        for shade in shades where shade.drawsAnything {
            let command = RoughRenderCommand(
                path: path,
                style: .fill(Color.clear),
                shade: shade
            )
            if shade.paintsOutside {
                after.append(command)
            } else {
                before.append(command)
            }
        }
        return (before, after)
    }

    static func draw(
        _ shade: InteriorShade,
        in path: SwiftUI.Path,
        context: inout GraphicsContext
    ) {
        guard shade.drawsAnything else { return }
        switch shade.kind {
        case let .innerShadow(opacity, x, y, blur, red, green, blue, alpha):
            drawInnerShadow(
                path: path,
                color: ink(red, green, blue, alpha, opacity: opacity),
                x: x,
                y: y,
                blur: blur,
                context: &context
            )
        case let .linear(stops, angle):
            drawLinear(path: path, stops: stops, angle: angle, context: &context)
        case let .radial(stops, centerX, centerY, startRadius, endRadius):
            drawRadial(
                path: path,
                stops: stops,
                centerX: centerX,
                centerY: centerY,
                startRadius: startRadius,
                endRadius: endRadius,
                context: &context
            )
        case let .halo(opacity, glow, width, blur, red, green, blue, alpha):
            drawHalo(
                path: path,
                band: ink(red, green, blue, alpha, opacity: opacity),
                glow: ink(red, green, blue, alpha, opacity: glow),
                width: width,
                blur: blur,
                context: &context
            )
        }
    }

    private static func drawInnerShadow(
        path: SwiftUI.Path,
        color: Color,
        x: CGFloat,
        y: CGFloat,
        blur: CGFloat,
        context: inout GraphicsContext
    ) {
        let box = path.boundingRect
        guard box.width > 0, box.height > 0 else { return }
        let pad = blur * 3 + abs(x) + abs(y) + 4
        var caster = SwiftUI.Path()
        caster.addRect(box.insetBy(dx: -pad, dy: -pad))
        caster.addPath(path)
        context.drawLayer { clipped in
            clipped.clip(to: path, style: SwiftUI.FillStyle(eoFill: true))
            clipped.drawLayer { source in
                source.addFilter(.shadow(color: color, radius: blur, x: x, y: y))
                source.fill(caster, with: .color(.black), style: SwiftUI.FillStyle(eoFill: true))
            }
        }
    }

    private static func drawLinear(
        path: SwiftUI.Path,
        stops: [ShadeStop],
        angle: CGFloat,
        context: inout GraphicsContext
    ) {
        let box = path.boundingRect
        guard box.width > 0, box.height > 0 else { return }
        let radians = angle * .pi / 180
        let dx = cos(radians)
        let dy = sin(radians)
        let start = CGPoint(x: box.midX - dx * box.width / 2, y: box.midY - dy * box.height / 2)
        let end = CGPoint(x: box.midX + dx * box.width / 2, y: box.midY + dy * box.height / 2)
        let gradient = Gradient(stops: stops.map {
            Gradient.Stop(color: $0.swiftColor, location: $0.location)
        })
        context.drawLayer { clipped in
            clipped.clip(to: path, style: SwiftUI.FillStyle(eoFill: true))
            clipped.fill(
                SwiftUI.Path(box),
                with: .linearGradient(gradient, startPoint: start, endPoint: end)
            )
        }
    }

    private static func drawRadial(
        path: SwiftUI.Path,
        stops: [ShadeStop],
        centerX: CGFloat,
        centerY: CGFloat,
        startRadius: CGFloat,
        endRadius: CGFloat,
        context: inout GraphicsContext
    ) {
        let box = path.boundingRect
        guard box.width > 0, box.height > 0 else { return }
        let reach = min(box.width, box.height) / 2
        let center = CGPoint(x: box.minX + centerX * box.width, y: box.minY + centerY * box.height)
        let gradient = Gradient(stops: stops.map {
            Gradient.Stop(color: $0.swiftColor, location: $0.location)
        })
        context.drawLayer { clipped in
            clipped.clip(to: path, style: SwiftUI.FillStyle(eoFill: true))
            clipped.fill(
                SwiftUI.Path(box),
                with: .radialGradient(
                    gradient,
                    center: center,
                    startRadius: startRadius * reach,
                    endRadius: endRadius * reach
                )
            )
        }
    }

    private static func drawHalo(
        path: SwiftUI.Path,
        band: Color,
        glow: Color,
        width: CGFloat,
        blur: CGFloat,
        context: inout GraphicsContext
    ) {
        context.drawLayer { layer in
            if blur > 0 {
                layer.addFilter(.shadow(color: glow, radius: blur, x: 0, y: 0))
            }
            layer.drawLayer { bandLayer in
                bandLayer.clip(to: path, style: SwiftUI.FillStyle(eoFill: true), options: .inverse)
                bandLayer.stroke(
                    path,
                    with: .color(band),
                    style: StrokeStyle(lineWidth: width * 2, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    private static func ink(
        _ red: CGFloat,
        _ green: CGFloat,
        _ blue: CGFloat,
        _ alpha: CGFloat,
        opacity: CGFloat
    ) -> Color {
        Color(
            .sRGB,
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            opacity: Double(min(1, max(0, alpha * opacity)))
        )
    }

    private static func bounds(of points: [CGPoint]) -> CGRect {
        var rect = CGRect.null
        for point in points {
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        return rect
    }
}
