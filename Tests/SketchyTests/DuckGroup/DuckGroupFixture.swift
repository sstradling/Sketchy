import CoreGraphics
import Foundation
import UIKit
@testable import Sketchy

/// The original Affinity duck (`seth-input-v3.svg`, viewBox 195×232).
///
/// Bitmap `<image>` and `<use>` nodes are dropped. Parts stay in source order.
/// `pad` and `scale` match the fixture fit. Stroke and fill weights stay in
/// points: this group does not multiply them by `scale`. The shadow scribble
/// in the fixture is `fillWeight` 2. The old custom renderer multiplied that
/// by the scale, so the preview passes 6 to keep the same wax on the scaled duck.
enum DuckGroupFixture {
    static let sourceOrder = [
        "left_foot", "body", "belly_shadow", "wing_shadow", "wing", "beak", "crest", "Eye", "right_foot"
    ]
    static let pad: CGFloat = 16
    static let scale: CGFloat = 3
    static let margin: CGFloat = 72
    static let viewBox = CGRect(x: 0, y: 0, width: 195, height: 232)
    static let seed: UInt64 = 17

    static var artSize: CGSize {
        let fitted = viewBox.insetBy(dx: -pad, dy: -pad)
        return CGSize(width: fitted.width * scale, height: fitted.height * scale)
    }

    static var canvasSize: CGSize {
        CGSize(width: artSize.width + margin * 2, height: artSize.height + margin * 2)
    }

    static var placement: CGAffineTransform {
        let fitted = viewBox.insetBy(dx: -pad, dy: -pad)
        let fit = CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: -fitted.minX * scale,
            ty: -fitted.minY * scale
        )
        return fit.concatenating(CGAffineTransform(translationX: margin, y: margin))
    }

    static func parts() throws -> [SketchPart] {
        guard let url = Bundle.module.url(
            forResource: "seth-input-v3",
            withExtension: "svg",
            subdirectory: "Fixtures"
        ) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let parsed = try DuckSVG.parse(String(contentsOf: url, encoding: .utf8))
        let byName = Dictionary(uniqueKeysWithValues: parsed.shapes.map { ($0.name, $0) })
        var parts: [SketchPart] = []
        for name in sourceOrder {
            guard let shape = byName[name] else { throw CocoaError(.fileReadCorruptFile) }
            var view = RoughView()
            view.options = options(for: name)
            view.drawables = [Path(d: shape.d)]
            parts.append(SketchPart(view).sketchTransform(shape.ctm.concatenating(placement)))
        }
        return parts
    }

    static func group(backing: StickerBacking?) throws -> SketchGroup {
        let built = try parts()
        var group = SketchGroup { built }
        if let backing {
            group = group.stickerBacking(backing).seed(seed)
        }
        return group
    }

    static func baseOptions() -> Options {
        var options = Options()
        options.strokeWidth = 15
        options.roughness = 0.6
        options.maxRandomnessOffset = 0.5
        options.bowing = 0.15
        options.strokeOpacity = 1
        options.fillStyle = .solid
        options.fillOpacity = 1
        options.stroke = .black
        options.fill = .clear
        options.seed = seed
        options.brushProfile = .crayon(
            grain: 0.2,
            edgeRoughness: 0.62,
            baseOpacity: 0.9,
            baseSoftness: 0.42,
            grit: 0.96,
            flakeSize: 1.2
        )
        return options
    }

    static func options(for name: String) -> Options {
        var options = baseOptions()
        let gold = color(0xF8CD5F)
        let darkGold = color(0xC7930C)
        switch name {
        case "left_foot":
            options.strokeWidth = 10
            options.fill = darkGold
        case "beak":
            options.strokeWidth = 9
            options.stroke = darkGold
            options.fill = gold
        case "Eye":
            options.fill = .black
            options.roughness = 0
            options.maxRandomnessOffset = 0
            options.bowing = 0
            options.brushProfile = .default
        case "right_foot":
            options.strokeWidth = 10
            options.fill = gold
        case "body", "wing":
            options.fill = color(0xFFFFFF)
        case "belly_shadow", "wing_shadow":
            options.fill = color(0xD7D1D8)
            options.fillStyle = .scribble
            options.scribbleTightness = 40
            options.scribbleOrigin = 100
            options.scribbleCurvature = 0
            options.scribbleUseBrushStroke = true
            options.fillWeight = 6
            options.fillOpacity = 0.9
            options.stroke = .clear
            options.strokeOpacity = 0
            options.brushProfile = .crayon(
                grain: 0.18,
                edgeRoughness: 0.85,
                widthVariation: 0.2,
                opacityVariation: 0.12,
                passes: 2,
                baseOpacity: 0.4,
                baseSoftness: 0.5,
                grit: 0.96,
                flakeSize: 1.8,
                seed: 5
            )
        case "crest":
            break
        default:
            preconditionFailure("Unexpected duck path \(name)")
        }
        return options
    }

    static func color(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Reads named paths from the duck SVG and drops bitmap uses.
final class DuckSVG: NSObject, XMLParserDelegate {
    struct Shape {
        var name: String
        var d: String
        var ctm: CGAffineTransform
    }

    private struct Frame {
        var ctm: CGAffineTransform
        var pushedName: Bool
    }

    private(set) var shapes: [Shape] = []
    private var frames: [Frame] = [Frame(ctm: .identity, pushedName: false)]
    private var names: [String] = []

    static func parse(_ svg: String) throws -> DuckSVG {
        var source = svg
        if let doctype = source.range(of: "<!DOCTYPE"),
           let end = source.range(of: ">", range: doctype.lowerBound..<source.endIndex) {
            source.removeSubrange(doctype.lowerBound..<end.upperBound)
        }
        let collector = DuckSVG()
        let parser = XMLParser(data: Data(source.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = collector
        guard parser.parse() else {
            throw parser.parserError ?? CocoaError(.fileReadCorruptFile)
        }
        return collector
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        let parent = frames.last?.ctm ?? .identity
        let local = Self.matrix(attributes["transform"]) ?? .identity
        let ctm = local.concatenating(parent)
        let name = attributes["id"]
        frames.append(Frame(ctm: ctm, pushedName: name != nil))
        if let name { names.append(name) }
        if elementName == "path" {
            shapes.append(Shape(
                name: name ?? names.last ?? "path-\(shapes.count + 1)",
                d: attributes["d"] ?? "",
                ctm: ctm
            ))
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let frame = frames.removeLast()
        if frame.pushedName { names.removeLast() }
    }

    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        Data()
    }

    private static func matrix(_ value: String?) -> CGAffineTransform? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("matrix("), trimmed.hasSuffix(")") else { return nil }
        let inner = trimmed.dropFirst("matrix(".count).dropLast()
        let parts = inner.split { $0 == "," || $0.isWhitespace }.compactMap { Double($0) }
        guard parts.count == 6 else { return nil }
        return CGAffineTransform(a: parts[0], b: parts[1], c: parts[2], d: parts[3], tx: parts[4], ty: parts[5])
    }
}
