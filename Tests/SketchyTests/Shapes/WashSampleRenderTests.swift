import SwiftUI
import UIKit
import XCTest
@testable import Sketchy

/// Renders sky-wash samples. Skipped unless `WASH_SAMPLES=1`.
@MainActor
final class WashSampleRenderTests: XCTestCase {
    func testRenderWashSamples() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["WASH_SAMPLES"] == "1",
            "Set WASH_SAMPLES=1 to write the wash samples."
        )
        let directory = ProcessInfo.processInfo.environment["WASH_SAMPLE_DIR"]
            ?? "/tmp/sketchy-wash-samples"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let sky = try render(SkyWashSample(), size: CGSize(width: 390, height: 640))
        let grass = try render(GrassWashSample(), size: CGSize(width: 390, height: 220))
        let curved = try render(ContourWashSample(), size: CGSize(width: 390, height: 360))
        try write(sky, named: "sky-wash.png", in: directory)
        try write(grass, named: "grass-60.png", in: directory)
        try write(curved, named: "contour-wash.png", in: directory)
    }

    private func render<V: View>(_ view: V, size: CGSize) throws -> UIImage {
        let framed = view.frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertGreaterThan(image.size.width, 1)
        return image
    }

    private func write(_ image: UIImage, named name: String, in directory: String) throws {
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: url)
        XCTAssertLessThan(data.count, 10 * 1_024 * 1_024, name)
    }
}

private struct SkyWashSample: View {
    var body: some View {
        RoughView()
            .fill(Color(red: 0.45, green: 0.62, blue: 0.98))
            .fillStyle(.wash)
            .fillAngle(-20)
            .washPasses(WashPass.sky(scale: 0.42))
            .brushProfile(.crayon)
            .stroke(Color.clear)
            .seed(0x51c7)
            .rectangle()
            .background(Color.white)
    }
}

private struct GrassWashSample: View {
    var body: some View {
        RoughView()
            .fill(Color(red: 0.20, green: 0.40, blue: 0.12))
            .fillStyle(.wash)
            .fillAngle(60)
            .washPasses(WashPass.sky(scale: 0.35))
            .brushProfile(.crayon)
            .stroke(Color.clear)
            .seed(60)
            .rectangle()
            .background(Color(red: 158 / 255, green: 214 / 255, blue: 96 / 255))
    }
}

private struct ContourWashSample: View {
    var body: some View {
        RoughView()
            .fill(Color(red: 0.20, green: 0.40, blue: 0.12))
            .fillStyle(.contour)
            .contourGuide(.arc(center: ContourPoint(x: 195, y: 640), radius: 420))
            .contourIntensity(from: 1, to: 0.4, angle: 90, easing: .easeInOut)
            .washPasses(WashPass.sky(scale: 0.28))
            .brushProfile(.crayon)
            .stroke(Color.clear)
            .seed(19)
            .rectangle()
            .background(Color(red: 158 / 255, green: 214 / 255, blue: 96 / 255))
    }
}
