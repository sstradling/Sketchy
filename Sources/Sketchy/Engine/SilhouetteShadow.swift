//
//  SilhouetteShadow.swift
//  Sketchy
//
//  A tinted alpha mask, skewed and pinned at an anchor.
//
//  Route: RoughView.draw(SilhouetteShadow) stores the value with the other
//  drawables. The canvas loop paints it directly and does not call the
//  generator, so it does not use Options.seed and it does not enter the
//  drawing cache. The same image, transform, and anchor repeat the same pixels.
//

import CoreGraphics
import SwiftUI
import UIKit

/// A ground shadow taken from an image's alpha.
///
/// The colour of the image is replaced by `color`. Transparent pixels stay
/// transparent. `transform` is applied around `anchor`, and `anchor` lands
/// on `position`. Y in `anchor` points down from the top of the image, in
/// points, matching a SwiftUI `Canvas`.
///
/// `tree(image:at:)` is the glider shadow: tint `rgb(22, 48, 14)`, opacity
/// `0.42`, skew `-0.58`, squash `0.32`, pinned on the lowest opaque row.
public struct SilhouetteShadow: Drawable, Equatable, Hashable {
    public var image: UIImage

    private var ink: RoughColor

    /// Tint that replaces the image colour. Alpha multiplies `opacity`.
    public var color: UIColor {
        get { ink.asUIColor }
        set { ink = RoughColor(uiColor: newValue) }
    }

    /// Strength from 0 to 1. `0` draws nothing. Default `0.42`.
    public var opacity: CGFloat

    /// Maps image points, after subtracting `anchor`, into the view.
    ///
    /// The glider shadow is `CGAffineTransform(a: 1, b: 0, c: -0.58, d: 0.32, tx: 0, ty: 0)`.
    public var transform: CGAffineTransform

    /// Point in the image, in points, that stays on `position`.
    public var anchor: CGPoint

    /// Where `anchor` is drawn, in view points.
    public var position: CGPoint

    public var method: String { "silhouetteShadow" }

    public var arguments: [Any] { [] }

    public init(
        image: UIImage,
        color: UIColor = UIColor(red: 22.0 / 255, green: 48.0 / 255, blue: 14.0 / 255, alpha: 1),
        opacity: CGFloat = 0.42,
        transform: CGAffineTransform = CGAffineTransform(a: 1, b: 0, c: -0.58, d: 0.32, tx: 0, ty: 0),
        anchor: CGPoint,
        position: CGPoint
    ) {
        self.image = image
        self.ink = RoughColor(uiColor: color)
        self.opacity = min(1, max(0, opacity))
        self.transform = transform
        self.anchor = anchor
        self.position = position
    }

    /// `color` is a SwiftUI color.
    public init(
        image: UIImage,
        color: Color,
        opacity: CGFloat = 0.42,
        transform: CGAffineTransform = CGAffineTransform(a: 1, b: 0, c: -0.58, d: 0.32, tx: 0, ty: 0),
        anchor: CGPoint,
        position: CGPoint
    ) {
        self.init(
            image: image,
            color: UIColor(color),
            opacity: opacity,
            transform: transform,
            anchor: anchor,
            position: position
        )
    }

    /// Same shadow from a mask image. Alpha, or a grayscale mask, is the shape.
    public init(
        mask: CGImage,
        color: UIColor = UIColor(red: 22.0 / 255, green: 48.0 / 255, blue: 14.0 / 255, alpha: 1),
        opacity: CGFloat = 0.42,
        transform: CGAffineTransform = CGAffineTransform(a: 1, b: 0, c: -0.58, d: 0.32, tx: 0, ty: 0),
        anchor: CGPoint,
        position: CGPoint,
        scale: CGFloat = 1
    ) {
        self.init(
            image: UIImage(cgImage: mask, scale: max(scale, 1), orientation: .up),
            color: color,
            opacity: opacity,
            transform: transform,
            anchor: anchor,
            position: position
        )
    }

    /// Glider tree shadow. The anchor is the middle of the lowest opaque row.
    public static func tree(
        image: UIImage,
        at position: CGPoint,
        color: UIColor = UIColor(red: 22.0 / 255, green: 48.0 / 255, blue: 14.0 / 255, alpha: 1),
        opacity: CGFloat = 0.42,
        skew: CGFloat = -0.58,
        squash: CGFloat = 0.32
    ) -> SilhouetteShadow {
        SilhouetteShadow(
            image: image,
            color: color,
            opacity: opacity,
            transform: CGAffineTransform(a: 1, b: 0, c: skew, d: squash, tx: 0, ty: 0),
            anchor: footAnchor(in: image),
            position: position
        )
    }

    /// Middle of the lowest row whose alpha is above `threshold`, in points.
    ///
    /// Y points down from the top of the image. An empty image returns the
    /// bottom centre.
    public static func footAnchor(in image: UIImage, alphaThreshold: UInt8 = 20) -> CGPoint {
        let width = image.size.width
        let height = image.size.height
        guard width > 0, height > 0, let cgImage = image.cgImage else {
            return CGPoint(x: width / 2, y: height)
        }
        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        guard pixelWidth > 0, pixelHeight > 0 else {
            return CGPoint(x: width / 2, y: height)
        }
        var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            return true
        }
        guard drew else { return CGPoint(x: width / 2, y: height) }

        // The bitmap's first row is the top of the image. The foot is the
        // last opaque row when y points down.
        let scaleX = width / CGFloat(pixelWidth)
        let scaleY = height / CGFloat(pixelHeight)
        var foot: CGPoint?
        for row in 0..<pixelHeight {
            var first: Int?
            var last: Int?
            for column in 0..<pixelWidth {
                let alpha = pixels[(row * pixelWidth + column) * 4 + 3]
                if alpha > alphaThreshold {
                    if first == nil { first = column }
                    last = column
                }
            }
            if let first, let last {
                let mid = CGFloat(first + last) / 2
                foot = CGPoint(x: (mid + 0.5) * scaleX, y: (CGFloat(row) + 0.5) * scaleY)
            }
        }
        return foot ?? CGPoint(x: width / 2, y: height)
    }

    public static func == (lhs: SilhouetteShadow, rhs: SilhouetteShadow) -> Bool {
        lhs.opacity == rhs.opacity
            && lhs.transform == rhs.transform
            && lhs.anchor == rhs.anchor
            && lhs.position == rhs.position
            && lhs.ink == rhs.ink
            && lhs.image.size == rhs.image.size
            && lhs.encodedBytes == rhs.encodedBytes
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(opacity)
        hasher.combine(transform.a)
        hasher.combine(transform.b)
        hasher.combine(transform.c)
        hasher.combine(transform.d)
        hasher.combine(transform.tx)
        hasher.combine(transform.ty)
        hasher.combine(anchor.x)
        hasher.combine(anchor.y)
        hasher.combine(position.x)
        hasher.combine(position.y)
        hasher.combine(ink)
        hasher.combine(image.size.width)
        hasher.combine(image.size.height)
        hasher.combine(encodedBytes)
    }

    private var encodedBytes: Data? {
        image.pngData()
    }
}
