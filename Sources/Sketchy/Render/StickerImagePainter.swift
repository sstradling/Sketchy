//
//  StickerImagePainter.swift
//  Sketchy
//
//  Masks a caller-supplied image to a sticker sheet.
//
//  Route: StickerBackingBuilder adds `RoughRenderCommand.stickerImage`.
//  SwiftUIRenderer and AnimatedRoughView call `StickerImagePainter.draw`
//  after the paper color. The sheet path is the mask, even-odd so holes
//  stay empty. A clip already on the context (the fallback hole cut) intersects
//  that mask.
//

import SwiftUI
import UIKit

/// Draws `image` inside `mask`. Does not fetch pixels. The image is already decoded.
enum StickerImagePainter {

    /// Most repeats drawn for one sheet. A smaller request is coarsened.
    static let tileBudget = 900

    static func draw(
        _ image: StickerImage,
        mask: SwiftUI.Path,
        fillRule: RoughFillRule,
        in context: inout GraphicsContext
    ) {
        guard image.opacity > 0.001, image.image.cgImage != nil else { return }
        let evenOdd = fillRule == .evenOdd
        var layer = context
        layer.opacity = image.opacity
        switch image.placement {
        case .tile:
            drawTiles(image, mask: mask, evenOdd: evenOdd, in: &layer)
        case .stretch:
            layer.clip(to: mask, style: SwiftUI.FillStyle(eoFill: evenOdd))
            layer.draw(Image(uiImage: image.image), in: fitted(mask.boundingRect, scale: image.resolvedFitScale))
        case .fill:
            layer.clip(to: mask, style: SwiftUI.FillStyle(eoFill: evenOdd))
            layer.draw(
                Image(uiImage: image.image),
                in: aspectFill(image.image.size, in: mask.boundingRect, scale: image.resolvedFitScale)
            )
        }
    }

    /// Repeat width after the sheet's tile budget. Tests use this for the cap.
    static func tileWidth(_ image: StickerImage, in bounds: CGRect) -> CGFloat {
        let aspect = max(image.image.size.height, 1) / max(image.image.size.width, 1)
        var width = image.resolvedTileWidth
        var height = max(4, width * aspect)
        let area = max(bounds.width, 1) * max(bounds.height, 1)
        let cell = width * height
        guard cell > 0 else { return width }
        let count = area / cell
        if count > CGFloat(tileBudget) {
            let growth = sqrt(count / CGFloat(tileBudget))
            width *= growth
            height *= growth
        }
        return width
    }

    private static func drawTiles(
        _ image: StickerImage,
        mask: SwiftUI.Path,
        evenOdd: Bool,
        in context: inout GraphicsContext
    ) {
        let bounds = mask.boundingRect
        guard bounds.width > 1, bounds.height > 1 else { return }
        let aspect = max(image.image.size.height, 1) / max(image.image.size.width, 1)
        let tileWidth = tileWidth(image, in: bounds)
        let tileHeight = max(4, tileWidth * aspect)
        context.clip(to: mask, style: SwiftUI.FillStyle(eoFill: evenOdd))
        let picture = Image(uiImage: image.image)
        var y = bounds.minY
        var rows = 0
        while y < bounds.maxY && rows < tileBudget {
            var x = bounds.minX
            var columns = 0
            while x < bounds.maxX && columns < tileBudget {
                context.draw(
                    picture,
                    in: CGRect(x: x, y: y, width: tileWidth, height: tileHeight)
                )
                x += tileWidth
                columns += 1
            }
            y += tileHeight
            rows += 1
        }
    }

    /// Bounds grown about the center by `scale`.
    private static func fitted(_ bounds: CGRect, scale: CGFloat) -> CGRect {
        let factor = max(scale, 0.05)
        let size = CGSize(width: bounds.width * factor, height: bounds.height * factor)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Rectangle that covers `bounds`, preserving the image aspect, then scaled.
    private static func aspectFill(_ imageSize: CGSize, in bounds: CGRect, scale: CGFloat) -> CGRect {
        let imageWidth = max(imageSize.width, 1)
        let imageHeight = max(imageSize.height, 1)
        let fit = max(bounds.width / imageWidth, bounds.height / imageHeight) * max(scale, 0.05)
        let size = CGSize(width: imageWidth * fit, height: imageHeight * fit)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
