//
//  InteriorShade.swift
//  Sketchy
//
//  Shades painted inside a closed shape, plus a soft band just outside it.
//
//  Route: `.interiorShades` on RoughView stores these on Options. The
//  generator does not read them and they do not consume Options.seed, so the
//  drawing cache key stays the shape's. SwiftUIRenderer inserts one command
//  per shade and InteriorShadePainter draws it. Clipped shades sit after the
//  fill and before the stroke. A halo is drawn after the stroke.
//

import CoreGraphics
import SwiftUI
import UIKit

/// One colour stop for an interior gradient.
///
/// `location` is clamped to `0...1`. `opacity` multiplies the colour's alpha
/// and is clamped to `0...1`.
public struct ShadeStop: Equatable, Hashable, Sendable {
    /// Position along the gradient. `0` is the start, `1` is the end.
    public var location: CGFloat

    /// Extra alpha, multiplied by the colour's own alpha.
    public var opacity: CGFloat

    fileprivate var red: CGFloat
    fileprivate var green: CGFloat
    fileprivate var blue: CGFloat
    fileprivate var alpha: CGFloat

    /// Stop colour. Alpha is kept and then multiplied by `opacity`.
    public var color: UIColor {
        get { UIColor(red: red, green: green, blue: blue, alpha: alpha) }
        set {
            let parts = InteriorShade.components(newValue)
            red = parts.red
            green = parts.green
            blue = parts.blue
            alpha = parts.alpha
        }
    }

    public init(location: CGFloat, color: UIColor, opacity: CGFloat = 1) {
        let parts = InteriorShade.components(color)
        self.location = min(1, max(0, location))
        self.opacity = min(1, max(0, opacity))
        self.red = parts.red
        self.green = parts.green
        self.blue = parts.blue
        self.alpha = parts.alpha
    }

    /// `color` is a SwiftUI color.
    public init(location: CGFloat, color: Color, opacity: CGFloat = 1) {
        self.init(location: location, color: UIColor(color), opacity: opacity)
    }

    var swiftColor: Color {
        Color(
            .sRGB,
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            opacity: Double(min(1, max(0, alpha * opacity)))
        )
    }
}

/// A shade clipped to a closed shape, or a soft band around its outline.
///
/// These do not change the generated sketch. An empty list draws nothing.
/// A line or other open contour is skipped. Holes stay empty: the clip is
/// even-odd, same as a solid fill.
///
/// `StickerShadow` is a drop shadow of the paper sheet and is not clipped
/// to the fill. An inner shadow is the opposite: the region outside the
/// shape casts into the shape, and the result is clipped to the interior.
public struct InteriorShade: Equatable, Hashable, Sendable {
    enum Kind: Equatable, Hashable, Sendable {
        case innerShadow(
            opacity: CGFloat,
            x: CGFloat,
            y: CGFloat,
            blur: CGFloat,
            red: CGFloat,
            green: CGFloat,
            blue: CGFloat,
            alpha: CGFloat
        )
        case linear(stops: [ShadeStop], angle: CGFloat)
        case radial(
            stops: [ShadeStop],
            centerX: CGFloat,
            centerY: CGFloat,
            startRadius: CGFloat,
            endRadius: CGFloat
        )
        case halo(
            opacity: CGFloat,
            glow: CGFloat,
            width: CGFloat,
            blur: CGFloat,
            red: CGFloat,
            green: CGFloat,
            blue: CGFloat,
            alpha: CGFloat
        )
    }

    var kind: Kind

    /// Shadow of the exterior, clipped to the interior.
    ///
    /// Positive `x` moves that shadow right. Positive `y` moves it down,
    /// which darkens the top of the opening. `blur` is the radius in points.
    /// `opacity` `0` draws nothing. The maze pits use `0.6`, offset `(0, 9)`,
    /// and blur `4`.
    public static func innerShadow(
        opacity: CGFloat = 0.6,
        x: CGFloat = 0,
        y: CGFloat = 9,
        blur: CGFloat = 4,
        color: UIColor = .black
    ) -> InteriorShade {
        let parts = components(color)
        return InteriorShade(kind: .innerShadow(
            opacity: min(1, max(0, opacity)),
            x: x,
            y: y,
            blur: max(0, blur),
            red: parts.red,
            green: parts.green,
            blue: parts.blue,
            alpha: parts.alpha
        ))
    }

    /// Same inner shadow. `color` is a SwiftUI color.
    public static func innerShadow(
        opacity: CGFloat = 0.6,
        x: CGFloat = 0,
        y: CGFloat = 9,
        blur: CGFloat = 4,
        color: Color
    ) -> InteriorShade {
        innerShadow(opacity: opacity, x: x, y: y, blur: blur, color: UIColor(color))
    }

    /// The small-pit inner shadow: 60% black, 9 points down, blur 4.
    public static var pitShadow: InteriorShade {
        innerShadow()
    }

    /// Linear gradient across the shape bounds, clipped to the interior.
    ///
    /// Angle `0` runs left to right. Angle `90` runs top to bottom, because
    /// y points down. An empty stop list draws nothing.
    public static func linear(_ stops: [ShadeStop], angle: CGFloat = 90) -> InteriorShade {
        InteriorShade(kind: .linear(stops: stops, angle: angle))
    }

    /// Vertical black recess on the small red pits.
    ///
    /// The top is black at 62% opacity, the middle at 40%, and the bottom at 22%.
    public static var pitRecess: InteriorShade {
        linear([
            ShadeStop(location: 0, color: Color.black, opacity: 0.62),
            ShadeStop(location: 0.62, color: Color.black, opacity: 0.4),
            ShadeStop(location: 1, color: Color.black, opacity: 0.22)
        ], angle: 90)
    }

    /// Radial gradient in the shape bounds, clipped to the interior.
    ///
    /// `center` is a unit point of those bounds. Radii are fractions of half
    /// the smaller side, so `1` reaches the inscribed circle. An empty stop
    /// list draws nothing.
    public static func radial(
        _ stops: [ShadeStop],
        center: UnitPoint = .center,
        startRadius: CGFloat = 0,
        endRadius: CGFloat = 1
    ) -> InteriorShade {
        InteriorShade(kind: .radial(
            stops: stops,
            centerX: center.x,
            centerY: center.y,
            startRadius: startRadius,
            endRadius: endRadius
        ))
    }

    /// Clear in the middle, then a colour at the rim.
    ///
    /// `inner` is the radius fraction where the colour starts. `1` is the
    /// inscribed circle. Used for the red rim on a spiral disc.
    public static func edgeShade(
        color: Color = Color(red: 0.86, green: 0.16, blue: 0.18),
        opacity: CGFloat = 0.55,
        inner: CGFloat = 0.62
    ) -> InteriorShade {
        let start = min(1, max(0, inner))
        return radial([
            ShadeStop(location: 0, color: color, opacity: 0),
            ShadeStop(location: start, color: color, opacity: 0),
            ShadeStop(location: 1, color: color, opacity: opacity)
        ])
    }

    /// Same rim shade with a `UIColor`.
    public static func edgeShade(
        color: UIColor,
        opacity: CGFloat = 0.55,
        inner: CGFloat = 0.62
    ) -> InteriorShade {
        edgeShade(color: Color(color), opacity: opacity, inner: inner)
    }

    /// A soft band just outside the outline, then a blur.
    ///
    /// `width` is the band thickness in points. The band is the outside half
    /// of a stroke, so it does not cover the fill. `opacity` is the band.
    /// `glow` is the blur colour's opacity. `blur` is the radius in points.
    /// The hit ring uses width `3.5`, opacity `0.55`, glow `0.3`, and blur `2`.
    public static func halo(
        color: UIColor,
        opacity: CGFloat = 0.55,
        glow: CGFloat = 0.3,
        width: CGFloat = 3.5,
        blur: CGFloat = 2
    ) -> InteriorShade {
        let parts = components(color)
        return InteriorShade(kind: .halo(
            opacity: min(1, max(0, opacity)),
            glow: min(1, max(0, glow)),
            width: max(0, width),
            blur: max(0, blur),
            red: parts.red,
            green: parts.green,
            blue: parts.blue,
            alpha: parts.alpha
        ))
    }

    /// Same halo. `color` is a SwiftUI color.
    public static func halo(
        color: Color,
        opacity: CGFloat = 0.55,
        glow: CGFloat = 0.3,
        width: CGFloat = 3.5,
        blur: CGFloat = 2
    ) -> InteriorShade {
        halo(color: UIColor(color), opacity: opacity, glow: glow, width: width, blur: blur)
    }

    var paintsOutside: Bool {
        if case .halo = kind { return true }
        return false
    }

    var drawsAnything: Bool {
        switch kind {
        case let .innerShadow(opacity, _, _, _, _, _, _, alpha):
            return opacity > 0 && alpha > 0
        case let .linear(stops, _):
            return stops.contains { $0.opacity > 0 && $0.alpha > 0 }
        case let .radial(stops, _, _, _, _):
            return stops.contains { $0.opacity > 0 && $0.alpha > 0 }
        case let .halo(opacity, glow, width, blur, _, _, _, alpha):
            return alpha > 0 && ((opacity > 0 && width > 0) || (glow > 0 && blur > 0))
        }
    }

    static func components(_ color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        if resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (red, green, blue, alpha)
        }
        return (0, 0, 0, 1)
    }
}
