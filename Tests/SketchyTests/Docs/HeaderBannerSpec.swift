import SwiftUI
@testable import Sketchy

/// How one letter of the README wordmark is drawn.
enum HeaderLetterRole: Equatable {
    /// Seeded `RoughView`, identical in every frame.
    case still
    /// Seeded `RoughView` on a white paper sheet (`StickerBacking`), identical in every frame.
    case sticker
    /// `AnimatedRoughView` pinned to one step per GIF frame.
    case animated
}

/// Ink, fill, and seed for one letter. Every letter carries its own seed so two renders match.
struct HeaderLetterSpec: Equatable {
    let character: Character
    let role: HeaderLetterRole
    let stroke: HeaderInk
    let fill: HeaderInk
    let fillStyle: Sketchy.FillStyle
    let fillAngle: Float
    let fillSpacing: Float
    let fillWeight: Float
    let roughness: Float
    let bowing: Float
    let strokeWidth: Float
    let seed: UInt64
    var dashOffset: Float = 0
    var dashGap: Float = 0
    var zigzagOffset: Float = 0
}

/// A colour written as a hex triple so the palette stays readable.
struct HeaderInk: Equatable {
    let hex: UInt32

    var color: Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Geometry shared by the wordmark view, the GIF renderer, and the tests. Units are points.
enum HeaderBannerLayout {
    static let width: CGFloat = 800
    static let height: CGFloat = 200
    static let cornerRadius: CGFloat = 14
    static let fontSize: CGFloat = 112
    static let fontName = "Bungee-Regular"
    static let tracking: CGFloat = 9
    /// Bungee cap height is 720/1000 em. Capitals span exactly four ruled lines.
    static let capHeight: CGFloat = fontSize * 0.72
    static let ruleGap: CGFloat = capHeight / 4
    static let baseline: CGFloat = 144
    static let marginX: CGFloat = 66
    /// Extra room around each letter's view so a sheet and its shadow are not clipped.
    static let letterPadding: CGFloat = 18
    /// Space between the sticker letter and the next one, so the sheet does not crowd it.
    static let stickerGap: CGFloat = 4
}

/// Frames, rate, and seeds for the GIF.
enum HeaderBannerAnimation {
    static let frameCount = 8
    static let fps = 10
    static let renderScale: CGFloat = 2
    static let config = AnimationConfig(steps: frameCount, speed: .fast, variance: .low, seed: 2025)
}

/// The paper sheet behind the leading `S`: white, smooth die-cut edge, with a soft cutout shadow.
///
/// The shadow is a SwiftUI shadow on the letter view, not `StickerBacking.shadow`. Bungee's S
/// has a notch narrower than the margin, so the sheet is built as a fill plus a round stroke
/// and `StickerShadow` is cast by both. The stroke's shadow lands on the paper inside the
/// letter as a grey smudge. A view shadow follows the finished silhouette instead.
enum HeaderSticker {
    static let backing = StickerBacking(
        width: 8,
        smoothness: 0.85,
        edge: .smooth,
        color: .white
    )

    static let shadowOpacity: Double = 0.3
    static let shadowRadius: CGFloat = 3
    static let shadowX: CGFloat = 0.5
    static let shadowY: CGFloat = 3

    /// How far the sheet and its shadow reach past the glyph outline, in points.
    static func reach(strokeWidth: CGFloat) -> CGFloat {
        backing.width + strokeWidth / 2 + abs(shadowY) + shadowRadius * 2
    }
}

/// The eight letters of "Sketchy!". Exactly one is a sticker and exactly one is animated.
enum HeaderBannerSpec {
    static let text = "Sketchy!"

    static let letters: [HeaderLetterSpec] = [
        HeaderLetterSpec(
            character: "S", role: .sticker,
            stroke: HeaderInk(hex: 0x132358), fill: HeaderInk(hex: 0x1F3A93),
            fillStyle: .hachure, fillAngle: -41, fillSpacing: 2.8, fillWeight: 1.7,
            roughness: 1.4, bowing: 1, strokeWidth: 2.4, seed: 707
        ),
        HeaderLetterSpec(
            character: "k", role: .still,
            stroke: HeaderInk(hex: 0x73221A), fill: HeaderInk(hex: 0xC0392B),
            fillStyle: .crossHatch, fillAngle: -30, fillSpacing: 8.5, fillWeight: 1.2,
            roughness: 2.2, bowing: 4, strokeWidth: 3, seed: 808
        ),
        HeaderLetterSpec(
            character: "e", role: .still,
            stroke: HeaderInk(hex: 0x12492A), fill: HeaderInk(hex: 0x1E7A46),
            fillStyle: .zigzag, fillAngle: 45, fillSpacing: 4.5, fillWeight: 1.2,
            roughness: 1.2, bowing: 1, strokeWidth: 2, seed: 909
        ),
        HeaderLetterSpec(
            character: "t", role: .still,
            stroke: HeaderInk(hex: 0x411F4F), fill: HeaderInk(hex: 0x6C3483),
            fillStyle: .dots, fillAngle: 0, fillSpacing: 4.8, fillWeight: 1.3,
            roughness: 1.0, bowing: 0.5, strokeWidth: 2.2, seed: 1010
        ),
        HeaderLetterSpec(
            character: "c", role: .still,
            stroke: HeaderInk(hex: 0x7F3200), fill: HeaderInk(hex: 0xD35400),
            fillStyle: .dashed, fillAngle: 30, fillSpacing: 6, fillWeight: 1.6,
            roughness: 0.6, bowing: 0.5, strokeWidth: 2.6, seed: 1111,
            dashOffset: 8, dashGap: 5
        ),
        HeaderLetterSpec(
            character: "h", role: .still,
            stroke: HeaderInk(hex: 0x0A4953), fill: HeaderInk(hex: 0x117A8B),
            fillStyle: .zigzagLine, fillAngle: 0, fillSpacing: 7, fillWeight: 1.2,
            roughness: 1.6, bowing: 2, strokeWidth: 1.6, seed: 1212,
            zigzagOffset: 2.5
        ),
        HeaderLetterSpec(
            character: "y", role: .still,
            stroke: HeaderInk(hex: 0x7B1E3A), fill: HeaderInk(hex: 0xE8A0B4),
            fillStyle: .solid, fillAngle: 0, fillSpacing: 3, fillWeight: 1,
            roughness: 1.7, bowing: 3, strokeWidth: 2.8, seed: 1313
        ),
        HeaderLetterSpec(
            character: "!", role: .animated,
            stroke: HeaderInk(hex: 0x6E5907), fill: HeaderInk(hex: 0xB7950B),
            fillStyle: .hachure, fillAngle: 0, fillSpacing: 3.2, fillWeight: 1.5,
            roughness: 1.8, bowing: 2, strokeWidth: 2.2, seed: 1414
        ),
    ]

    /// The seeded drawing of one letter. The sticker sheet is added to `.sticker` only.
    @MainActor
    static func roughView(for letter: HeaderLetterSpec, font: UIFont, padding: CGFloat) -> RoughView {
        var view = RoughView()
            .fill(letter.fill.color)
            .fillStyle(letter.fillStyle)
            .fillAngle(letter.fillAngle)
            .fillSpacing(letter.fillSpacing)
            .fillWeight(letter.fillWeight)
            .stroke(letter.stroke.color)
            .strokeWidth(letter.strokeWidth)
            .roughness(letter.roughness)
            .bowing(letter.bowing)
            .seed(letter.seed)
        if letter.dashOffset > 0 { view = view.dashOffset(letter.dashOffset) }
        if letter.dashGap > 0 { view = view.dashGap(letter.dashGap) }
        if letter.zigzagOffset > 0 { view = view.zigzagOffset(letter.zigzagOffset) }
        if letter.role == .sticker { view = view.stickerBacking(HeaderSticker.backing) }
        return view.text(
            String(letter.character),
            font: font,
            horizontalAlignment: .leading,
            verticalAlignment: .top,
            offsetX: padding,
            offsetY: padding
        )
    }
}
