import SwiftUI
import XCTest
@testable import Sketchy

/// Modifier-rendered duck cards. Skipped unless `GROUP_STICKER_PREVIEW=1`
/// is in the simulator process environment (`simctl spawn … launchctl setenv`).
@MainActor
final class DuckGroupPreviewTests: XCTestCase {

    func testRenderDuckGroupPreviews() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GROUP_STICKER_PREVIEW"] == "1"
            || environment["TEST_RUNNER_GROUP_STICKER_PREVIEW"] == "1" else {
            throw XCTSkip("Set GROUP_STICKER_PREVIEW=1 to write the duck group cards.")
        }
        let directory = URL(fileURLWithPath: environment["GROUP_STICKER_OUTPUT"]
            ?? environment["TEST_RUNNER_GROUP_STICKER_OUTPUT"]
            ?? "/private/var/folders/nw/t6y3z2zx761_d2mj042hh58r0000gn/T/cursor_agent_stores/bc-59affe9b-5aa0-5087-888d-6c277694fe99/files/group-sticker-preview",
            isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let torn = try DuckGroupFixture.group(backing: Self.torn)
        let smooth = try DuckGroupFixture.group(backing: Self.smooth)
        let plain = try DuckGroupFixture.group(backing: nil)
        let size = DuckGroupFixture.canvasSize

        try write(card("Whole duck, one white torn sheet", duck(torn, size: size)), name: "duck-group-torn.png", to: directory)
        try write(
            card("Torn, smooth, and no shared sheet") {
                HStack(alignment: .top, spacing: 28) {
                    column("Torn", duck(torn, size: size))
                    column("Smooth", duck(smooth, size: size))
                    column("No backing", duck(plain, size: size))
                }
            },
            name: "duck-group-compare.png",
            to: directory
        )
    }

    func testDuckSilhouetteIsOneSheetWithoutInternalHoles() throws {
        let parts = try DuckGroupFixture.parts()
        let lines = SketchGroupRenderer.silhouetteLines(
            parts: parts,
            backing: StickerBacking(
                width: 22,
                smoothness: 0.5,
                edge: .torn(StickerTear(depth: 7, length: 22, jaggedness: 0.26))
            ),
            size: DuckGroupFixture.canvasSize
        )
        XCTAssertFalse(lines.isEmpty)
        let areas = lines.map { abs(Self.area($0.points)) }
        let largest = areas.max() ?? 0
        XCTAssertGreaterThan(largest, 80_000, "the shared hull should cover the duck, not a sliver")
        let meaningful = lines.filter { abs(Self.area($0.points)) > largest * 0.02 }
        XCTAssertEqual(meaningful.count, 1, "disconnected specks are fine; a second body is not")
        for line in lines {
            let sample = Self.centroid(line.points)
            let ringArea = abs(Self.area(line.points))
            let containers = lines.filter {
                abs(Self.area($0.points)) > ringArea * 1.05 && Self.contains(sample, $0.points)
            }
            XCTAssertTrue(containers.isEmpty, "an interior ring would cut a halo")
        }
    }

    private static func area(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            sum += points[index].x * next.y - next.x * points[index].y
        }
        return sum * 0.5
    }

    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let count = CGFloat(max(points.count, 1))
        return CGPoint(x: sum.x / count, y: sum.y / count)
    }

    private static func contains(_ point: CGPoint, _ ring: [CGPoint]) -> Bool {
        var inside = false
        var previous = ring.count - 1
        for index in ring.indices {
            let currentY = ring[index].y
            let previousY = ring[previous].y
            if (currentY > point.y) != (previousY > point.y) {
                let x = (ring[previous].x - ring[index].x) * (point.y - currentY) / (previousY - currentY) + ring[index].x
                if point.x < x { inside.toggle() }
            }
            previous = index
        }
        return inside
    }

    private static let torn = StickerBacking(
        width: 22,
        smoothness: 0.5,
        edge: .torn(StickerTear(depth: 7, length: 22, jaggedness: 0.26)),
        color: UIColor.white,
        texture: .paper(amount: 0.45, scale: 11, seed: 17)
    )

    private static let smooth = StickerBacking(
        width: 22,
        smoothness: 0.5,
        edge: .smooth,
        color: UIColor.white,
        texture: .paper(amount: 0.45, scale: 11, seed: 17)
    )

    private func duck(_ group: SketchGroup, size: CGSize) -> some View {
        group.frame(width: size.width, height: size.height)
    }

    private func column<V: View>(_ title: String, _ content: V) -> some View {
        VStack(spacing: 12) {
            content
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(white: 0.96))
        }
    }

    private func card<V: View>(_ title: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color(white: 0.96))
            content()
        }
        .padding(36)
        .background(Color(red: 0.22, green: 0.31, blue: 0.39))
    }

    private func card(_ title: String, _ content: some View) -> some View {
        card(title) { content }
    }

    private func write<V: View>(_ content: V, name: String, to directory: URL) throws {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.isOpaque = true
        let image = try XCTUnwrap(renderer.uiImage, "No image for \(name)")
        let data = try XCTUnwrap(image.pngData(), "No PNG for \(name)")
        XCTAssertLessThan(data.count, 10 * 1024 * 1024, "\(name) exceeds 10 MB")
        XCTAssertGreaterThan(data.count, 20 * 1024, "\(name) looks empty")
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
