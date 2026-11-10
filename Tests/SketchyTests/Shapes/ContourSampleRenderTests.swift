import SwiftUI
import UIKit
import XCTest
@testable import Sketchy

/// Renders the Glider, flatten, brush, graduation, and drift samples.
///
/// Skipped unless `CONTOUR_SAMPLES=1`. Writes PNGs and a GIF under
/// `CONTOUR_SAMPLE_DIR`, or `/tmp/sketchy-contour-samples`.
@MainActor
final class ContourSampleRenderTests: XCTestCase {
    func testRenderContourSamples() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CONTOUR_SAMPLES"] == "1",
            "Set CONTOUR_SAMPLES=1 to write the contour sample images."
        )
        let directory = ProcessInfo.processInfo.environment["CONTOUR_SAMPLE_DIR"]
            ?? "/tmp/sketchy-contour-samples"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let glider = try render(GliderDomeSample(), size: CGSize(width: 420, height: 780))
        let flatten = try render(FlattenComparisonSample(), size: CGSize(width: 760, height: 520))
        let brushes = try render(BrushProfileSample(), size: CGSize(width: 780, height: 300))
        let graduated = try render(GraduatedCurvatureSample(), size: CGSize(width: 720, height: 320))
        try write(glider, named: "glider-dome.png", in: directory)
        try write(flatten, named: "flatten-off-vs-on.png", in: directory)
        try write(brushes, named: "brush-profiles.png", in: directory)
        try write(graduated, named: "graduated-curvature.png", in: directory)

        let frames = 8
        let speed: Float = 40
        for index in 0..<frames {
            // One second of travel at 40 points per second, sampled across the frames.
            let phase = speed * Float(index) / Float(frames - 1)
            let frame = try render(
                DriftFrameSample(phase: phase),
                size: CGSize(width: 420, height: 280)
            )
            try write(frame, named: String(format: "drift-%02d.png", index), in: directory)
        }
    }

    private func render<V: View>(_ view: V, size: CGSize) throws -> UIImage {
        let framed = view.frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        if let image = renderer.uiImage, image.size.width > 1 {
            return image
        }
        let host = UIHostingController(rootView: framed)
        host.view.bounds = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .white
        let window = UIWindow(frame: host.view.bounds)
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertGreaterThan(image.size.width, 1)
        return image
    }

    private func write(_ image: UIImage, named name: String, in directory: String) throws {
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
        guard let data = image.pngData() else {
            XCTFail("no png for \(name)")
            return
        }
        try data.write(to: url)
        XCTAssertLessThan(data.count, 10 * 1_024 * 1_024, name)
    }
}

private struct GliderDomeSample: View {
    private let width: Float = 420
    private let height: Float = 780
    private let crest: Float = 300
    private let radius: Float = 520

    var body: some View {
        let center = ContourPoint(x: width / 2, y: crest + radius)
        let guide = ContourGuide.arc(center: center, radius: radius)
        let dome = Polygon(points: domePoints)
        ZStack {
            Color(red: 0.78, green: 0.88, blue: 0.98)
            RoughView()
                .fill(Color(red: 158 / 255, green: 214 / 255, blue: 96 / 255))
                .fillStyle(.solid)
                .stroke(Color.clear)
                .roughness(0)
                .seed(1)
                .draw(dome)
            grassPass(guide: guide, dome: dome, weight: 15, spacing: 1.15, opacity: 62, seed: 1400)
            grassPass(guide: guide, dome: dome, weight: 10, spacing: 1.65, opacity: 45, seed: 2600)
            lake(guide: guide, center: CGPoint(x: 90, y: 460), radius: CGSize(width: 58, height: 22))
            lake(guide: guide, center: CGPoint(x: 310, y: 540), radius: CGSize(width: 72, height: 28))
            lake(guide: guide, center: CGPoint(x: 150, y: 660), radius: CGSize(width: 84, height: 34))
        }
    }

    private var domePoints: [Point] {
        var points: [Point] = []
        let steps = 42
        let cy = crest + radius
        for index in 0...steps {
            let x = width * Float(index) / Float(steps)
            let dx = x - width / 2
            let inside = radius * radius - dx * dx
            let y = inside > 1 ? cy - sqrt(inside) : cy
            points.append(Point(x: x, y: y))
        }
        points.append(Point(x: width, y: height))
        points.append(Point(x: 0, y: height))
        return points
    }

    private func grassPass(
        guide: ContourGuide,
        dome: Polygon,
        weight: Float,
        spacing: Float,
        opacity: Float,
        seed: UInt64
    ) -> some View {
        RoughView()
            .fill(Color(red: 0.20, green: 0.40, blue: 0.12))
            .fillStyle(.contour)
            .contourGuide(guide)
            .contourIntensity(from: 1, to: 0.42, angle: 90, easing: .easeInOut)
            .contourFalloff(0.72)
            .fillWeight(weight)
            .fillSpacing(spacing)
            .fillOpacity(opacity)
            .stroke(Color.clear)
            .roughness(1.5)
            .bowing(1.1)
            .maxRandomnessOffset(2)
            .brushProfile(.crayon)
            .seed(seed)
            .draw(dome)
    }

    private func lake(guide: ContourGuide, center: CGPoint, radius: CGSize) -> some View {
        let shape = Polygon(points: blob(center: center, radius: radius))
        return ZStack {
            RoughView()
                .fill(Color(red: 118 / 255, green: 196 / 255, blue: 230 / 255))
                .fillStyle(.solid)
                .stroke(Color.clear)
                .roughness(0)
                .seed(3)
                .draw(shape)
            RoughView()
                .fill(Color(red: 0.16, green: 0.34, blue: 0.48))
                .fillStyle(.contour)
                .contourGuide(guide)
                .contourIntensity(from: 1, to: 0.5, angle: 90, easing: .easeInOut)
                .contourFalloff(0.35)
                .fillWeight(7)
                .fillSpacing(1.3)
                .fillOpacity(70)
                .stroke(Color.clear)
                .roughness(1.3)
                .bowing(1)
                .brushProfile(.crayon)
                .seed(90)
                .draw(shape)
        }
    }
}

private struct FlattenComparisonSample: View {
    var body: some View {
        HStack(spacing: 16) {
            panel(title: "Intensity 1", end: 1)
            panel(title: "Intensity 1 to 0.35", end: 0.35)
        }
        .padding(16)
        .background(Color.white)
    }

    private func panel(title: String, end: Float) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            dome(end: end)
                .frame(width: 340, height: 430)
        }
    }

    private func dome(end: Float) -> some View {
        let width: Float = 340
        let height: Float = 430
        let crest: Float = 70
        let radius: Float = 380
        let center = ContourPoint(x: width / 2, y: crest + radius)
        var points: [Point] = []
        for index in 0...36 {
            let x = width * Float(index) / 36
            let dx = x - width / 2
            let inside = radius * radius - dx * dx
            let y = inside > 1 ? center.y - sqrt(inside) : center.y
            points.append(Point(x: x, y: y))
        }
        points.append(Point(x: width, y: height))
        points.append(Point(x: 0, y: height))
        let dome = Polygon(points: points)
        let guide = ContourGuide.arc(center: center, radius: radius)
        return ZStack {
            RoughView()
                .fill(Color(red: 158 / 255, green: 214 / 255, blue: 96 / 255))
                .fillStyle(.solid)
                .stroke(Color.clear)
                .roughness(0)
                .seed(2)
                .draw(dome)
            RoughView()
                .fill(Color(red: 0.20, green: 0.40, blue: 0.12))
                .fillStyle(.contour)
                .contourGuide(guide)
                .contourIntensity(from: 1, to: end, angle: 90, easing: .linear)
                .fillWeight(8)
                .fillSpacing(2.2)
                .stroke(Color.clear)
                .roughness(0.4)
                .bowing(0.4)
                .seed(11)
                .draw(dome)
        }
    }
}

private struct BrushProfileSample: View {
    var body: some View {
        HStack(spacing: 12) {
            tile("Crayon", profile: .crayon, seed: 21)
            tile("Marker", profile: .marker, seed: 22)
            tile("Pen", profile: .pen, seed: 23)
        }
        .padding(12)
        .background(Color.white)
    }

    private func tile(_ title: String, profile: BrushProfile, seed: UInt64) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.headline)
            RoughView()
                .fill(Color(red: 0.18, green: 0.42, blue: 0.62))
                .fillStyle(.contour)
                .contourGuide(.arc(center: ContourPoint(x: 120, y: 320), radius: 240))
                .contourIntensity(0.9)
                .fillWeight(10)
                .fillSpacing(2.4)
                .stroke(Color(red: 0.12, green: 0.14, blue: 0.18))
                .strokeWidth(2)
                .roughness(1.2)
                .bowing(1)
                .brushProfile(profile)
                .seed(seed)
                .rectangle()
        }
        .frame(width: 240, height: 270)
    }
}

private struct GraduatedCurvatureSample: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Curvature 0 at the left, 1.8 at the right")
                .font(.headline)
            RoughView()
                .fill(Color(red: 0.20, green: 0.40, blue: 0.12))
                .fillStyle(.contour)
                .contourGuide(.arc(center: ContourPoint(x: 360, y: 980), radius: 820))
                .contourIntensity(from: 0, to: 1.8, angle: 0, easing: .easeInOut)
                .fillWeight(7)
                .fillSpacing(2.6)
                .stroke(Color.clear)
                .roughness(0.3)
                .bowing(0.2)
                .brushProfile(.crayon)
                .seed(31)
                .rectangle()
        }
        .padding(16)
        .background(Color(red: 0.96, green: 0.97, blue: 0.94))
    }
}

private struct DriftFrameSample: View {
    var phase: Float

    var body: some View {
        VStack(spacing: 6) {
            Text("Drift 40 pt/s at 90°  phase \(Int(phase)) pt")
                .font(.headline)
            RoughView()
                .fill(Color(red: 0.18, green: 0.46, blue: 0.67))
                .fillStyle(.contour)
                .contourGuide(.arc(center: ContourPoint(x: 210, y: 520), radius: 360))
                .contourIntensity(0.85)
                .fillWeight(8)
                .fillSpacing(2.8)
                .stroke(Color.clear)
                .roughness(1.1)
                .bowing(0.8)
                .seed(44)
                .contourDrift(angle: 90, speed: 0, phase: phase)
                .rectangle()
        }
        .padding(12)
        .background(Color.white)
    }
}

private func blob(center: CGPoint, radius: CGSize) -> [Point] {
    (0..<18).map { index in
        let angle = Float(index) / 18 * 2 * Float.pi
        return Point(
            x: Float(center.x) + Float(radius.width) * cos(angle),
            y: Float(center.y) + Float(radius.height) * sin(angle)
        )
    }
}
