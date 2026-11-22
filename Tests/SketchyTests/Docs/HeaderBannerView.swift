import CoreText
import SwiftUI
import UIKit
@testable import Sketchy

/// Where one letter's view sits on the card, in points.
struct HeaderLetterPlacement {
    let spec: HeaderLetterSpec
    /// Top-left of the letter's padded view.
    let origin: CGPoint
    let size: CGSize
}

/// Positions the letters of the wordmark from Bungee's metrics.
enum HeaderBannerLayoutSolver {
    /// Advance width of one character, in points.
    static func advance(of character: Character, font: UIFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: String(character), attributes: [.font: font])
        )
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Distance from the top of the typographic box to the baseline.
    static func ascent(of font: UIFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: "H", attributes: [.font: font])
        )
        var ascent: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, nil, nil)
        return ascent
    }

    /// Letters centered in the paper right of the margin rule, baseline on a ruled line.
    ///
    /// The text drawable aligns ink to the view's left edge, so each view starts at the
    /// glyph's left side bearing past its pen position.
    static func placements(font: UIFont) -> [HeaderLetterPlacement] {
        let pad = HeaderBannerLayout.letterPadding
        let specs = HeaderBannerSpec.letters
        let advances = specs.map { advance(of: $0.character, font: font) }
        let total = advances.reduce(0, +)
            + HeaderBannerLayout.tracking * CGFloat(specs.count - 1)
            + HeaderBannerLayout.stickerGap
        let areaLeft = HeaderBannerLayout.marginX + 10
        let areaRight = HeaderBannerLayout.width - 14
        var pen = areaLeft + (areaRight - areaLeft - total) / 2
        let top = HeaderBannerLayout.baseline - ascent(of: font) - pad
        let boxHeight = font.ascender + abs(font.descender)

        var result: [HeaderLetterPlacement] = []
        for (index, spec) in specs.enumerated() {
            let ink = TextPathConverter.boundingBox(for: String(spec.character), font: font)
            let size = CGSize(width: ink.width + pad * 2, height: boxHeight + pad * 2)
            result.append(HeaderLetterPlacement(
                spec: spec,
                origin: CGPoint(x: pen + ink.minX - pad, y: top),
                size: size
            ))
            pen += advances[index] + HeaderBannerLayout.tracking
            if spec.role == .sticker { pen += HeaderBannerLayout.stickerGap }
        }
        return result
    }
}

/// The README wordmark for one GIF frame: ruled paper card, seven static letters, one boiling `!`.
@MainActor
struct HeaderBannerView: View {
    let frame: Int
    let font: UIFont

    var body: some View {
        ZStack(alignment: .topLeading) {
            HeaderPaper()
            ForEach(Array(HeaderBannerLayoutSolver.placements(font: font).enumerated()), id: \.offset) { _, placement in
                letter(placement)
                    .frame(width: placement.size.width, height: placement.size.height)
                    .position(
                        x: placement.origin.x + placement.size.width / 2,
                        y: placement.origin.y + placement.size.height / 2
                    )
            }
        }
        .frame(width: HeaderBannerLayout.width, height: HeaderBannerLayout.height)
        .environment(\.colorScheme, .light)
        .transaction { $0.disablesAnimations = true }
    }

    @ViewBuilder
    private func letter(_ placement: HeaderLetterPlacement) -> some View {
        let rough = HeaderBannerSpec.roughView(
            for: placement.spec,
            font: font,
            padding: HeaderBannerLayout.letterPadding
        )
        switch placement.spec.role {
        case .animated:
            AnimatedRoughView(config: HeaderBannerAnimation.config, roughView: rough)
                .pinnedFrame(frame)
        case .sticker:
            rough.shadow(
                color: .black.opacity(HeaderSticker.shadowOpacity),
                radius: HeaderSticker.shadowRadius,
                x: HeaderSticker.shadowX,
                y: HeaderSticker.shadowY
            )
        case .still:
            rough
        }
    }
}

/// Cream notebook paper with a margin rule and two punched holes. Rounded corners stay transparent.
struct HeaderPaper: View {
    private static let paper = Color(red: 0.992, green: 0.976, blue: 0.933)
    private static let rule = Color(red: 0.612, green: 0.765, blue: 0.902)
    private static let margin = Color(red: 0.898, green: 0.451, blue: 0.451)
    private static let edge = Color(red: 0.80, green: 0.76, blue: 0.67)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HeaderBannerLayout.cornerRadius, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(Self.paper)
            Canvas { context, size in
                var y = HeaderBannerLayout.baseline
                while y > 0 { y -= HeaderBannerLayout.ruleGap }
                while y < size.height {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(line, with: .color(Self.rule), lineWidth: 1)
                    y += HeaderBannerLayout.ruleGap
                }
                for (dx, width, opacity) in [(0.0, 1.4, 1.0), (4.0, 0.7, 0.7)] {
                    var rule = Path()
                    rule.move(to: CGPoint(x: HeaderBannerLayout.marginX + dx, y: 0))
                    rule.addLine(to: CGPoint(x: HeaderBannerLayout.marginX + dx, y: size.height))
                    context.stroke(rule, with: .color(Self.margin.opacity(opacity)), lineWidth: width)
                }
                for fraction in [0.3, 0.7] {
                    let hole = CGRect(x: 30 - 7, y: size.height * fraction - 7, width: 14, height: 14)
                    context.fill(Path(ellipseIn: hole), with: .color(Color(red: 0.937, green: 0.91, blue: 0.839)))
                    context.stroke(
                        Path(ellipseIn: hole),
                        with: .color(Color(red: 0.867, green: 0.827, blue: 0.733)),
                        lineWidth: 1
                    )
                }
            }
            shape.strokeBorder(Self.edge, lineWidth: 1)
        }
        .clipShape(shape)
        .frame(width: HeaderBannerLayout.width, height: HeaderBannerLayout.height)
    }
}
