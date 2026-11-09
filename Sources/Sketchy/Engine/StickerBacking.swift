//
//  StickerBacking.swift
//  Sketchy
//
//  Opt-in paper behind a drawing, like a die-cut sticker or a paper cutout.
//

import SwiftUI
import UIKit

/// How the paper edge is cut.
public enum StickerEdge: Equatable, Hashable, Sendable {
    /// Curves between real corners. An egg can still show the sampled
    /// silhouette's vertices. Star points and rectangle corners stay sharp.
    case smooth

    /// Continuous tangent around the whole sheet, including the closed seam.
    ///
    /// Corners of the silhouette are rounded on purpose. This is separate
    /// from `StickerBacking.smoothness`, which only chooses the rough outline
    /// or the input silhouette. `radius` is how far along the edge the
    /// rounding reaches, in points. `0` picks a radius from the outline
    /// length that removes sampled facets.
    case fullySmooth(radius: CGFloat = 0)

    /// Chopped facets. `depth` of `0` uses 55% of the backing width, at least
    /// 3 points. The same `Options.seed` repeats the chops.
    case torn(StickerTear = StickerTear())
}

/// Facets along a torn or chopped paper edge.
///
/// `depth` is how far a facet may sit inside or outside the smooth contour,
/// in points. `0` asks the renderer to use `max(3, width * 0.55)`.
/// `length` is the nominal facet length in points. `jaggedness` (`0...1`)
/// adds smaller nicks on each facet.
public struct StickerTear: Equatable, Hashable, Sendable {
    /// Peak chip size in points. `0` selects an automatic depth from the width.
    public var depth: CGFloat

    /// Nominal length of one chopped facet, in points. Minimum 4.
    public var length: CGFloat

    /// Extra nicks along a facet, from 0 (flat chops) to 1.
    public var jaggedness: CGFloat

    public init(depth: CGFloat = 0, length: CGFloat = 16, jaggedness: CGFloat = 0.35) {
        self.depth = max(0, depth)
        self.length = max(4, length)
        self.jaggedness = min(1, max(0, jaggedness))
    }

    /// Depth in points. A stored `depth` of `0` follows the backing width.
    func resolvedDepth(width: CGFloat) -> CGFloat {
        if depth > 0 {
            return depth
        }
        return max(3, width * 0.55)
    }
}

/// Paper grain drawn inside a sticker sheet.
///
/// The grain is short fibers on the paper color. It does not change the
/// sketch stroke or fill. `nil` texture on `StickerBacking` is a flat color.
/// The same `seed` repeats the fibers. A `nil` seed uses `Options.seed`, then
/// a fixed seed. Fibers are clipped to the sheet, including around holes.
public struct StickerTexture: Equatable, Hashable, Sendable {
    /// How visible the grain is, from 0 (flat) to 1 (strong). Default 0.45.
    public var amount: CGFloat

    /// Spacing of the fiber grid, in points. Larger values are coarser. Minimum 4.
    public var scale: CGFloat

    /// Stable grain seed. `nil` follows `Options.seed`.
    public var seed: UInt64?

    public init(amount: CGFloat = 0.45, scale: CGFloat = 11, seed: UInt64? = nil) {
        self.amount = min(1, max(0, amount))
        self.scale = max(4, scale)
        self.seed = seed
    }

    /// A visible sheet of paper. `amount` 0.45, `scale` 11 points.
    public static func paper(amount: CGFloat = 0.45, scale: CGFloat = 11, seed: UInt64? = nil) -> StickerTexture {
        StickerTexture(amount: amount, scale: scale, seed: seed)
    }
}

/// How a supplied image sits inside the sticker mask.
public enum StickerImagePlacement: Equatable, Hashable, Sendable {
    /// Repeat the image across the sheet. `StickerImage.scale` is the width of
    /// one repeat in points. `0` uses the image's point width.
    case tile

    /// Stretch the image to the sheet's bounding box.
    case stretch

    /// Scale the image uniformly so it covers the bounding box. The mask crops it.
    case fill
}

/// An image masked by the sticker silhouette.
///
/// The caller supplies a decoded `UIImage` (a PNG or any other format
/// `UIImage` can read from memory). Sketchy does not fetch a URL. The sheet
/// path, including torn and fully smooth edges and holes, is the mask. The
/// base `StickerBacking.color` is painted first, so transparent pixels and
/// `opacity` below 1 show that color. Paper fibers, when set, draw on top.
///
/// For `.tile`, `scale` is the repeat width in points. `0` uses the image's
/// own point size. Widths below 4 points are raised to 4. A sheet that would
/// need more than about 900 repeats is given a coarser repeat.
/// For `.stretch` and `.fill`, `scale` multiplies the fitted size. `0` and `1`
/// both mean "fit the bounds".
public struct StickerImage: Equatable, Hashable {
    /// Decoded image. Draw this; do not load it from the network.
    public var image: UIImage

    /// Tile, stretch, or aspect-fill.
    public var placement: StickerImagePlacement

    /// Tile width in points, or a multiplier for stretch and fill. See the type discussion.
    public var scale: CGFloat

    /// Strength of the image over the paper color, from 0 to 1.
    public var opacity: CGFloat

    public init(
        image: UIImage,
        placement: StickerImagePlacement = .tile,
        scale: CGFloat = 0,
        opacity: CGFloat = 1
    ) {
        self.image = image
        self.placement = placement
        self.scale = scale.isFinite && scale > 0 ? scale : 0
        self.opacity = min(1, max(0, opacity))
    }

    /// Decodes PNG, JPEG, or another `UIImage` format from memory.
    /// Returns nil when `data` is not an image.
    public init?(
        data: Data,
        placement: StickerImagePlacement = .tile,
        scale: CGFloat = 0,
        opacity: CGFloat = 1
    ) {
        guard let image = UIImage(data: data) else { return nil }
        self.init(image: image, placement: placement, scale: scale, opacity: opacity)
    }

    /// Repeat width in points after the 4-point minimum. Ignores the 900-repeat cap.
    var resolvedTileWidth: CGFloat {
        let natural = max(image.size.width, 1)
        return max(4, scale > 0 ? scale : natural)
    }

    /// Multiplier for `.stretch` and `.fill`. `0` means 1.
    var resolvedFitScale: CGFloat {
        scale > 0 ? scale : 1
    }

    public static func == (lhs: StickerImage, rhs: StickerImage) -> Bool {
        lhs.placement == rhs.placement
            && lhs.scale == rhs.scale
            && lhs.opacity == rhs.opacity
            && lhs.image.size == rhs.image.size
            && lhs.encodedBytes == rhs.encodedBytes
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(placement)
        hasher.combine(scale)
        hasher.combine(opacity)
        hasher.combine(image.size.width)
        hasher.combine(image.size.height)
        hasher.combine(encodedBytes)
    }

    /// PNG bytes when the image can be encoded. Equality uses the whole buffer.
    private var encodedBytes: Data? {
        image.pngData()
    }
}

/// A drop shadow of the finished cutout, not of the ink.
///
/// Leave `StickerBacking.shadow` nil and nothing is added. `opacity` `0`, or
/// a shadow with no offset and no blur, also draws nothing, so an opaque
/// sheet stays pixel-identical to an unshadowed one.
///
/// `x` and `y` are points in the canvas, after `sketchTransform`. Positive
/// `x` moves the shadow to the right. Positive `y` moves it down. `radius`
/// is the blur, in the same points. Neither value is multiplied by
/// `sketchScale`. A SwiftUI scale on the whole view scales the rendered
/// shadow with the sheet.
///
/// The shadow follows the finished sheet: smooth, fully smooth, or torn,
/// including holes and separate pieces. It is drawn behind the paper and is
/// not clipped to the fill. The canvas bounds still clip it, so leave room
/// of about `abs(offset) + radius * 2` or the blur is cut off. Fibers and
/// the sketch are painted after the shadow and do not cast their own.
public struct StickerShadow: Equatable, Hashable, Sendable {
    /// Strength from 0 (invisible) to 1. Default 0.35.
    public var opacity: CGFloat

    /// Horizontal shift of the shadow, in points. Positive is right.
    public var x: CGFloat

    /// Vertical shift of the shadow, in points. Positive is down.
    public var y: CGFloat

    /// Blur radius in points. `0` is a hard shadow. Default 8.
    public var radius: CGFloat

    private var inkColor: RoughColor

    /// Shadow color. Default is black. Alpha is multiplied by `opacity`.
    public var color: UIColor {
        get { inkColor.asUIColor }
        set { inkColor = RoughColor(uiColor: newValue) }
    }

    public init(
        opacity: CGFloat = 0.35,
        x: CGFloat = 0,
        y: CGFloat = 8,
        radius: CGFloat = 8,
        color: UIColor = .black
    ) {
        self.opacity = min(1, max(0, opacity))
        self.x = x
        self.y = y
        self.radius = max(0, radius)
        self.inkColor = RoughColor(uiColor: color)
    }

    /// `color` is a SwiftUI color. Pass `Color.black` when both overloads are visible.
    public init(
        opacity: CGFloat = 0.35,
        x: CGFloat = 0,
        y: CGFloat = 8,
        radius: CGFloat = 8,
        color: Color
    ) {
        self.init(opacity: opacity, x: x, y: y, radius: radius, color: UIColor(color))
    }
}

/// Paper drawn behind a shape's fill and stroke.
///
/// Leave `Options.stickerBacking` nil to draw nothing extra. A value does not
/// change the generated outline or fill, and it does not consume `Options.seed`
/// for the sketch. Torn edges read that seed on their own.
///
/// `width` is the white (or `color`) margin past the nominal stroke, in
/// points. The sheet extends `width + strokeWidth / 2` from the outline
/// centerline, so the ink sits on the paper and the margin shows beyond it.
/// `smoothness` blends that contour from the rough outline (`0`) toward the
/// input silhouette (`1`): fine sketch wobble leaves, and a star stays a
/// star. `1` does not replace the shape with a blob. A shape with no
/// silhouette guide is simplified by the same amount instead.
///
/// Closed contours, including SVG subpaths and glyph outlines, become a filled
/// sheet. Holes stay holes (even-odd), with the same margin inside the cutout.
/// The second rough pass over the same contour is not a second sheet. Open
/// contours (lines, curves, open arcs, and legacy per-edge strokes) become a
/// paper ribbon of `strokeWidth + 2 * width` instead of a filled cutout.
/// `.strokeContinuity(.legacy)` is that open-edge case for rectangles and
/// polygons. Use `.continuous` (the default) for a die-cut sheet.
///
/// A notch tighter than the margin, or a torn edge that would cross itself,
/// does not emit a self-intersecting fill. The torn depth is reduced first.
/// If the outward offset still crosses, that closed contour is a round
/// dilation (filled centerline plus a round stroke) rather than a mitered ring.
/// An image on that fallback is masked to the interior and to the stroke
/// margin, and is kept out of hole interiors. Fibers on that fallback still
/// clip to the interior only.
public struct StickerBacking: Equatable, Hashable {
    /// Margin past the nominal stroke, in points. `0` draws no paper.
    public var width: CGFloat

    /// `0` follows the rough outline. `1` removes fine wobble and keeps the
    /// silhouette. Values outside `0...1` are clamped.
    public var smoothness: CGFloat

    /// Smooth die-cut edge, or chopped paper.
    ///
    /// `.smooth` draws the sheet as curves between real corners, so an egg
    /// or circle stays a continuous outline. Star points and rectangle
    /// corners stay sharp. `.torn` keeps the chopped facets.
    public var edge: StickerEdge

    /// Fibers on the sheet. `nil` draws no fibers. Independent of `image`.
    public var texture: StickerTexture?

    /// Image masked by the sheet. `nil` is the flat color, plus fibers when set.
    public var image: StickerImage?

    private var paperColor: RoughColor

    /// Paper color. Default is white. Alpha is honored.
    public var color: UIColor {
        get { paperColor.asUIColor }
        set { paperColor = RoughColor(uiColor: newValue) }
    }

    /// Drop shadow of this sheet. `nil` draws none.
    public var shadow: StickerShadow?

    public init(
        width: CGFloat,
        smoothness: CGFloat = 0,
        edge: StickerEdge = .smooth,
        color: UIColor = .white,
        texture: StickerTexture? = nil,
        image: StickerImage? = nil,
        shadow: StickerShadow? = nil
    ) {
        self.width = max(0, width)
        self.smoothness = min(1, max(0, smoothness))
        self.edge = Self.clamped(edge)
        self.texture = texture
        self.image = image
        self.paperColor = RoughColor(uiColor: color)
        self.shadow = shadow
    }

    /// Same sheet with a drop shadow. `nil` removes it.
    public func shadow(_ shadow: StickerShadow?) -> StickerBacking {
        var copy = self
        copy.shadow = shadow
        return copy
    }

    /// Same sheet with a drop shadow. `color` defaults to black.
    public func shadow(
        opacity: CGFloat = 0.35,
        x: CGFloat = 0,
        y: CGFloat = 8,
        radius: CGFloat = 8,
        color: Color = Color.black
    ) -> StickerBacking {
        shadow(StickerShadow(opacity: opacity, x: x, y: y, radius: radius, color: color))
    }

    /// Same sheet with a drop shadow in a `UIColor`. `color` is required.
    public func shadow(
        opacity: CGFloat = 0.35,
        x: CGFloat = 0,
        y: CGFloat = 8,
        radius: CGFloat = 8,
        color: UIColor
    ) -> StickerBacking {
        shadow(StickerShadow(opacity: opacity, x: x, y: y, radius: radius, color: color))
    }

    private static func clamped(_ edge: StickerEdge) -> StickerEdge {
        switch edge {
        case .smooth:
            return .smooth
        case .fullySmooth(let radius):
            return .fullySmooth(radius: max(0, radius))
        case .torn(let tear):
            return .torn(StickerTear(
                depth: tear.depth,
                length: tear.length,
                jaggedness: tear.jaggedness
            ))
        }
    }
}
