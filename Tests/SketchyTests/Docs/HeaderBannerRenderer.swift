import CoreGraphics
import CoreText
import SwiftUI
import UIKit

/// Failure while rasterizing the README wordmark frames.
enum HeaderBannerError: Error, CustomStringConvertible {
    case missingFont(String)
    case fontRegistration(String)
    case imageRenderFailed(Int)
    case unexpectedPixelSize(Int, Int, Int)
    case pngEncodingFailed(Int)
    case outputNotWritable
    case staticRegionChanged(Int)
    case framesIdentical

    var description: String {
        switch self {
        case let .missingFont(detail):
            return "Bungee-Regular.ttf was not found. \(detail)"
        case let .fontRegistration(detail):
            return "Could not register Bungee: \(detail)"
        case let .imageRenderFailed(index):
            return "ImageRenderer returned no image for header frame \(index)."
        case let .unexpectedPixelSize(index, width, height):
            return "Header frame \(index) is \(width)x\(height) px."
        case let .pngEncodingFailed(index):
            return "Could not encode header frame \(index)."
        case .outputNotWritable:
            return "Could not write the header render directory."
        case let .staticRegionChanged(index):
            return "Header frame \(index) differs from frame 0 outside the animated '!'."
        case .framesIdentical:
            return "Header frames are identical, so the '!' did not animate."
        }
    }
}

/// Manifest read by `scripts/render-header.sh`.
struct HeaderManifest: Encodable {
    var frameCount: Int
    var fps: Int
    var pixelWidth: Int
    var pixelHeight: Int
}

/// Renders the animated wordmark frames. `scripts/render-header.sh` assembles them into a GIF.
@MainActor
enum HeaderBannerRenderer {
    /// Registers Bungee (once per process) and returns it at the header size.
    static func loadFont() throws -> UIFont {
        let environment = ProcessInfo.processInfo.environment
        let path = ["TEST_RUNNER_HEADER_FONT", "HEADER_FONT"]
            .compactMap { environment[$0] }
            .first { !$0.isEmpty }
        if UIFont(name: HeaderBannerLayout.fontName, size: HeaderBannerLayout.fontSize) == nil {
            guard let path, FileManager.default.fileExists(atPath: path) else {
                throw HeaderBannerError.missingFont("Set HEADER_FONT to its path, or run scripts/render-header.sh.")
            }
            var error: Unmanaged<CFError>?
            let url = URL(fileURLWithPath: path) as CFURL
            if !CTFontManagerRegisterFontsForURL(url, .process, &error) {
                let detail = error?.takeRetainedValue().localizedDescription ?? "unknown error"
                throw HeaderBannerError.fontRegistration(detail)
            }
        }
        guard let font = UIFont(name: HeaderBannerLayout.fontName, size: HeaderBannerLayout.fontSize) else {
            throw HeaderBannerError.fontRegistration("\(HeaderBannerLayout.fontName) is not available after registration.")
        }
        return font
    }

    /// Picks a writable directory. The simulator strips `TEST_RUNNER_` from forwarded variables.
    static func resolveOutputDirectory() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [URL] = []
        for key in ["TEST_RUNNER_HEADER_OUTPUT", "HEADER_OUTPUT"] {
            if let path = environment[key], !path.isEmpty {
                candidates.append(URL(fileURLWithPath: path, isDirectory: true))
            }
        }
        candidates.append(
            FileManager.default.temporaryDirectory.appending(path: "sketchy-header", directoryHint: .isDirectory)
        )
        for candidate in candidates where probe(candidate) {
            return candidate
        }
        throw HeaderBannerError.outputNotWritable
    }

    /// Renders every frame as `frame-NN.png` and writes `manifest.json` into `directory`.
    static func render(to directory: URL) throws {
        let font = try loadFont()
        let scale = HeaderBannerAnimation.renderScale
        let expectedWidth = Int((HeaderBannerLayout.width * scale).rounded())
        let expectedHeight = Int((HeaderBannerLayout.height * scale).rounded())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var baseline: [UInt8]?
        var anyDifference = false
        let staticColumns = try staticColumnCount(font: font, scale: scale)
        for index in 0..<HeaderBannerAnimation.frameCount {
            let renderer = ImageRenderer(content: HeaderBannerView(frame: index, font: font))
            renderer.scale = scale
            renderer.proposedSize = ProposedViewSize(width: HeaderBannerLayout.width, height: HeaderBannerLayout.height)
            renderer.isOpaque = false
            guard let image = renderer.uiImage, let cgImage = image.cgImage else {
                throw HeaderBannerError.imageRenderFailed(index)
            }
            guard cgImage.width == expectedWidth, cgImage.height == expectedHeight else {
                throw HeaderBannerError.unexpectedPixelSize(index, cgImage.width, cgImage.height)
            }
            let pixels = rgba(cgImage)
            if let baseline {
                if !sameStaticRegion(pixels, baseline, width: cgImage.width, columns: staticColumns) {
                    throw HeaderBannerError.staticRegionChanged(index)
                }
                anyDifference = anyDifference || pixels != baseline
            } else {
                baseline = pixels
            }
            guard let data = image.pngData() else { throw HeaderBannerError.pngEncodingFailed(index) }
            let name = String(format: "frame-%02d.png", index)
            try data.write(to: directory.appending(path: name), options: .atomic)
        }
        guard anyDifference else { throw HeaderBannerError.framesIdentical }

        let manifest = HeaderManifest(
            frameCount: HeaderBannerAnimation.frameCount,
            fps: HeaderBannerAnimation.fps,
            pixelWidth: expectedWidth,
            pixelHeight: expectedHeight
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: directory.appending(path: "manifest.json"), options: .atomic)
        NSLog("HEADER_RENDER_OUTPUT=%@", directory.path)
    }

    /// Pixel columns left of the `!` view. Every one of them must match across frames.
    private static func staticColumnCount(font: UIFont, scale: CGFloat) throws -> Int {
        guard let bang = HeaderBannerLayoutSolver.placements(font: font)
            .first(where: { $0.spec.role == .animated }) else { return 0 }
        return max(0, Int(((bang.origin.x - 1) * scale).rounded(.down)))
    }

    private static func sameStaticRegion(_ a: [UInt8], _ b: [UInt8], width: Int, columns: Int) -> Bool {
        guard a.count == b.count, width > 0 else { return false }
        let rowBytes = width * 4
        let compareBytes = columns * 4
        var row = 0
        while row * rowBytes < a.count {
            let start = row * rowBytes
            if a[start..<start + compareBytes] != b[start..<start + compareBytes] { return false }
            row += 1
        }
        return true
    }

    private static func rgba(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }

    private static func probe(_ url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let marker = url.appending(path: ".write-probe")
            try Data("ok".utf8).write(to: marker, options: .atomic)
            try FileManager.default.removeItem(at: marker)
            return true
        } catch {
            return false
        }
    }
}
