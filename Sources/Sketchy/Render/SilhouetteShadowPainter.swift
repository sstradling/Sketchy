//
//  SilhouetteShadowPainter.swift
//  Sketchy
//
//  Draws SilhouetteShadow into a GraphicsContext.
//
//  RoughView calls this before the generator. The image is tinted once per
//  draw. The transform is applied around the anchor, then the anchor is
//  moved to `position`.
//

import SwiftUI
import UIKit

enum SilhouetteShadowPainter {
    static func draw(_ shadow: SilhouetteShadow, in context: inout GraphicsContext) {
        guard shadow.opacity > 0.001 else { return }
        guard shadow.image.size.width > 0, shadow.image.size.height > 0 else { return }
        guard let tinted = tint(shadow.image, color: shadow.color) else { return }
        let alpha = min(1, max(0, shadow.opacity * CGFloat(shadow.color.cgColor.alpha)))
        context.drawLayer { layer in
            layer.translateBy(x: shadow.position.x, y: shadow.position.y)
            layer.concatenate(shadow.transform)
            layer.translateBy(x: -shadow.anchor.x, y: -shadow.anchor.y)
            layer.opacity = alpha
            layer.draw(
                Image(uiImage: tinted),
                in: CGRect(origin: .zero, size: shadow.image.size)
            )
        }
    }

    /// Replaces the image colour and keeps its alpha.
    private static func tint(_ image: UIImage, color: UIColor) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let painted = renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            ctx.cgContext.setBlendMode(.sourceIn)
            ctx.cgContext.setFillColor(color.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: image.size))
        }
        return painted
    }
}
