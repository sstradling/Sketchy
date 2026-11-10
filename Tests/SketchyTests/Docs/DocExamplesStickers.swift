import SwiftUI
import UIKit
@testable import Sketchy

extension DocExampleCatalog {
    /// Five-point star inside the 184-point card. The slate mat is gallery chrome.
    private static let stickerStarPoints = """
        Point(x: 92, y: 36),
        Point(x: 106, y: 73),
        Point(x: 145, y: 75),
        Point(x: 115, y: 99),
        Point(x: 125, y: 137),
        Point(x: 92, y: 116),
        Point(x: 59, y: 137),
        Point(x: 69, y: 99),
        Point(x: 39, y: 75),
        Point(x: 78, y: 73)
    """

    private static func stickerStar() -> Polygon {
        Polygon(points: [
            Point(x: 92, y: 36),
            Point(x: 106, y: 73),
            Point(x: 145, y: 75),
            Point(x: 115, y: 99),
            Point(x: 125, y: 137),
            Point(x: 92, y: 116),
            Point(x: 59, y: 137),
            Point(x: 69, y: 99),
            Point(x: 39, y: 75),
            Point(x: 78, y: 73)
        ])
    }

    static let stickerExamples: [DocExample] = [
        still(
            "sticker-star",
            section: "Stickers",
            title: "Sticker star",
            description: "White paper past the stroke. Smoothness 0.85 follows the star and drops the sketch wobble. The slate mat is only in the gallery so the white margin shows.",
            snippet: """
            RoughView()
                .fill(\(inkBlue.snippet))
                .fillStyle(.hachure)
                .fillAngle(0)
                .fillSpacing(3)
                .stroke(\(charcoal.snippet))
                .strokeWidth(2)
                .roughness(1.4)
                .seed(42)
                .stickerBacking(width: 14, smoothness: 0.85)
                .draw(Polygon(points: [
                    \(stickerStarPoints)
                ]))
            """,
            picture: .stickerMat
        ) {
            RoughView()
                .fill(inkBlue.color)
                .fillStyle(.hachure)
                .fillAngle(0)
                .fillSpacing(3)
                .stroke(charcoal.color)
                .strokeWidth(2)
                .roughness(1.4)
                .seed(42)
                .stickerBacking(width: 14, smoothness: 0.85)
                .draw(stickerStar())
        },
        still(
            "sticker-torn",
            section: "Stickers",
            title: "Torn sticker",
            description: "The same star with a chopped edge. Depth, facet length, and jaggedness are seeded, so the tear repeats.",
            snippet: """
            RoughView()
                .fill(\(coral.snippet))
                .fillStyle(.hachure)
                .fillAngle(0)
                .fillSpacing(3)
                .stroke(\(charcoal.snippet))
                .strokeWidth(2)
                .roughness(1.4)
                .seed(42)
                .stickerBacking(
                    width: 16,
                    smoothness: 0.55,
                    edge: .torn(StickerTear(depth: 7, length: 14, jaggedness: 0.45))
                )
                .draw(Polygon(points: [
                    \(stickerStarPoints)
                ]))
            """,
            picture: .stickerMat
        ) {
            RoughView()
                .fill(coral.color)
                .fillStyle(.hachure)
                .fillAngle(0)
                .fillSpacing(3)
                .stroke(charcoal.color)
                .strokeWidth(2)
                .roughness(1.4)
                .seed(42)
                .stickerBacking(
                    width: 16,
                    smoothness: 0.55,
                    edge: .torn(StickerTear(depth: 7, length: 14, jaggedness: 0.45))
                )
                .draw(stickerStar())
        },
        still(
            "sticker-crayon",
            section: "Stickers",
            title: "Crayon on paper",
            description: "The wax stroke paints on top of the sheet. A wider margin keeps most of the grit on the paper.",
            snippet: """
            RoughView()
                .fill(\(plum.snippet))
                .fillStyle(.hachure)
                .fillAngle(0)
                .fillSpacing(3.5)
                .stroke(\(plum.snippet))
                .strokeWidth(12)
                .brushProfile(.crayon(seed: 4))
                .seed(4)
                .stickerBacking(width: 18, smoothness: 0.7)
                .circle()
            """,
            picture: .stickerMat
        ) {
            RoughView()
                .fill(plum.color)
                .fillStyle(.hachure)
                .fillAngle(0)
                .fillSpacing(3.5)
                .stroke(plum.color)
                .strokeWidth(12)
                .brushProfile(.crayon(seed: 4))
                .seed(4)
                .stickerBacking(width: 18, smoothness: 0.7)
                .circle()
        },
        still(
            "sticker-paper",
            section: "Stickers",
            title: "Tinted paper",
            description: "The sheet color and the grain are separate. Fibers stay inside the cutout and repeat with the texture seed.",
            snippet: """
            RoughView()
                .fill(\(leaf.snippet))
                .fillStyle(.hachure)
                .fillAngle(0)
                .fillSpacing(3)
                .stroke(\(charcoal.snippet))
                .strokeWidth(2)
                .seed(18)
                .stickerBacking(
                    width: 16,
                    smoothness: 0.8,
                    color: Color(red: 0.96, green: 0.91, blue: 0.78),
                    texture: .paper(amount: 0.55, scale: 10, seed: 18)
                )
                .egg(tilt: 0.4)
            """,
            picture: .stickerMat
        ) {
            RoughView()
                .fill(leaf.color)
                .fillStyle(.hachure)
                .fillAngle(0)
                .fillSpacing(3)
                .stroke(charcoal.color)
                .strokeWidth(2)
                .seed(18)
                .stickerBacking(
                    width: 16,
                    smoothness: 0.8,
                    color: Color(red: 0.96, green: 0.91, blue: 0.78),
                    texture: .paper(amount: 0.55, scale: 10, seed: 18)
                )
                .egg(tilt: 0.4)
        },
        still(
            "sticker-fully-smooth",
            section: "Stickers",
            title: "Fully smooth edge",
            description: "fullySmooth rounds the whole cutout, including corners of the sampled egg. smoothness still only chooses the silhouette. The slate mat is gallery chrome.",
            snippet: """
            RoughView()
                .fill(\(leaf.snippet))
                .fillStyle(.hachure)
                .fillAngle(0)
                .fillSpacing(3)
                .stroke(\(charcoal.snippet))
                .strokeWidth(2)
                .seed(17)
                .stickerBacking(width: 22, smoothness: 1, edge: .fullySmooth())
                .draw(EggShape(x: 92, y: 98, width: 72, height: 104, tilt: 0.42))
            """,
            picture: .stickerMat
        ) {
            RoughView()
                .fill(leaf.color)
                .fillStyle(.hachure)
                .fillAngle(0)
                .fillSpacing(3)
                .stroke(charcoal.color)
                .strokeWidth(2)
                .seed(17)
                .stickerBacking(width: 22, smoothness: 1, edge: .fullySmooth())
                .draw(EggShape(x: 92, y: 98, width: 72, height: 104, tilt: 0.42))
        },
        still(
            "sticker-image",
            section: "Stickers",
            title: "Image mask",
            description: "A watercolor-paper photo is masked by the sheet. The paper color shows through transparent pixels. Photo from Unsplash. The slate mat is gallery chrome.",
            snippet: """
            let paper = UIImage(named: "watercolor-paper") ?? UIImage()
            RoughView()
                .fill(\(leaf.snippet))
                .fillStyle(.hachure)
                .fillAngle(0)
                .fillSpacing(3)
                .stroke(\(charcoal.snippet))
                .strokeWidth(2)
                .seed(21)
                .stickerBacking(
                    width: 32,
                    smoothness: 1,
                    image: StickerImage(image: paper, placement: .fill)
                )
                .draw(EggShape(x: 92, y: 98, width: 72, height: 104, tilt: 0.42))
            """,
            picture: .stickerMat
        ) {
            RoughView()
                .fill(leaf.color)
                .fillStyle(.hachure)
                .fillAngle(0)
                .fillSpacing(3)
                .stroke(charcoal.color)
                .strokeWidth(2)
                .seed(21)
                .stickerBacking(
                    width: 32,
                    smoothness: 1,
                    image: StickerImage(
                        image: WatercolorPaperFixture.image() ?? UIImage(),
                        placement: .fill
                    )
                )
                .draw(EggShape(x: 92, y: 98, width: 72, height: 104, tilt: 0.42))
        },
        still(
            "sticker-group",
            section: "Stickers",
            title: "Shared sheet",
            description: "SketchGroup gives both circles one sheet. sketchOffset moves the second circle. SwiftUI offset would not. The slate mat is gallery chrome.",
            snippet: """
            SketchGroup {
                RoughView()
                    .fill(\(inkBlue.snippet))
                    .fillStyle(.hachure)
                    .fillAngle(0)
                    .fillSpacing(3)
                    .stroke(\(charcoal.snippet))
                    .strokeWidth(2)
                    .seed(7)
                    .draw(Circle(x: 78, y: 96, diameter: 78))
                SketchPart(
                    RoughView()
                        .fill(\(coral.snippet))
                        .fillStyle(.hachure)
                        .fillAngle(0)
                        .fillSpacing(3)
                        .stroke(\(charcoal.snippet))
                        .strokeWidth(2)
                        .seed(7)
                        .draw(Circle(x: 78, y: 96, diameter: 62))
                )
                .sketchOffset(x: 34, y: 6)
            }
            .stickerBacking(width: 12, smoothness: 0.7, color: Color.white)
            .seed(7)
            """,
            picture: .stickerGroup
        ) {
            RoughView()
                .fill(inkBlue.color)
                .fillStyle(.hachure)
                .fillAngle(0)
                .fillSpacing(3)
                .stroke(charcoal.color)
                .strokeWidth(2)
                .seed(7)
                .draw(Circle(x: 78, y: 96, diameter: 78))
        },
        still(
            "sticker-shadow",
            section: "Stickers",
            title: "Cutout shadow",
            description: "One shadow of the sheet. opacity, x, y, and radius are points. Leave padding or the view clips the blur. The slate mat is gallery chrome.",
            snippet: """
            RoughView()
                .fill(\(inkBlue.snippet))
                .fillStyle(.hachure)
                .fillAngle(0)
                .fillSpacing(3)
                .stroke(\(charcoal.snippet))
                .strokeWidth(2)
                .seed(11)
                .stickerBacking(
                    width: 12,
                    smoothness: 0.8,
                    color: Color.white,
                    shadow: StickerShadow(opacity: 0.4, x: 0, y: 8, radius: 6, color: Color.black)
                )
                .draw(EggShape(x: 92, y: 84, width: 64, height: 86, tilt: 0.2))
            """,
            picture: .stickerMat
        ) {
            RoughView()
                .fill(inkBlue.color)
                .fillStyle(.hachure)
                .fillAngle(0)
                .fillSpacing(3)
                .stroke(charcoal.color)
                .strokeWidth(2)
                .seed(11)
                .stickerBacking(
                    width: 12,
                    smoothness: 0.8,
                    color: Color.white,
                    shadow: StickerShadow(opacity: 0.4, x: 0, y: 8, radius: 6, color: Color.black)
                )
                .draw(EggShape(x: 92, y: 84, width: 64, height: 86, tilt: 0.2))
        },
        still(
            "tree-shadow",
            section: "Stickers",
            title: "Tree shadow",
            description: "SilhouetteShadow.tree tints the sprite alpha rgb(22, 48, 14) at 42%, skews it -0.58, squashes it to 0.32, and pins the lowest opaque row.",
            snippet: """
            RoughView()
                .seed(19)
                .draw(SilhouetteShadow.tree(image: sprite, at: CGPoint(x: 120, y: 156)))
            """
        ) {
            RoughView()
                .seed(19)
                .draw(SilhouetteShadow.tree(image: docTreeSprite(), at: CGPoint(x: 120, y: 156)))
        }
    ]
}

private func docTreeSprite() -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    return UIGraphicsImageRenderer(size: CGSize(width: 44, height: 78), format: format).image { ctx in
        let context = ctx.cgContext
        context.setFillColor(UIColor(red: 0.22, green: 0.55, blue: 0.28, alpha: 1).cgColor)
        context.fillEllipse(in: CGRect(x: 2, y: 4, width: 40, height: 36))
        context.fill(CGRect(x: 18, y: 30, width: 8, height: 46))
    }
}

struct DocStickerGroupCard: View {
    var body: some View {
        SketchGroup {
            RoughView()
                .fill(DocExampleCatalog.inkBlue.color)
                .fillStyle(.hachure)
                .fillAngle(0)
                .fillSpacing(3)
                .stroke(DocExampleCatalog.charcoal.color)
                .strokeWidth(2)
                .seed(7)
                .draw(Circle(x: 78, y: 96, diameter: 78))
            SketchPart(
                RoughView()
                    .fill(DocExampleCatalog.coral.color)
                    .fillStyle(.hachure)
                    .fillAngle(0)
                    .fillSpacing(3)
                    .stroke(DocExampleCatalog.charcoal.color)
                    .strokeWidth(2)
                    .seed(7)
                    .draw(Circle(x: 78, y: 96, diameter: 62))
            )
            .sketchOffset(x: 34, y: 6)
        }
        .stickerBacking(width: 12, smoothness: 0.7, color: Color.white)
        .seed(7)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.27, green: 0.36, blue: 0.43))
        )
    }
}