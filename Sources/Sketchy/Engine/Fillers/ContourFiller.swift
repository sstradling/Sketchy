//
//  ContourFiller.swift
//  Sketchy
//
//  Curved fill strokes that follow a guide and keep the rough-stroke pipeline.
//

import Foundation

/// Fills a shape with rough strokes that follow `Options.contourGuide`.
///
/// Each stroke is a curved centerline, then `curveOps` adds the same bowing
/// and roughness as other line fills. A crayon or marker brush still strokes
/// those centerlines. Width falloff is grouped into bands so each band is one
/// stroke width.
public struct ContourFiller: FillGenerator {
    public init() {}

    public func fillPolygon(points: [[Float]], options: Options) -> OperationSet? {
        let sets = fillPolygonSets(points: points, options: options)
        guard !sets.isEmpty else { return nil }
        if sets.count == 1 {
            return sets[0]
        }
        return OperationSet(
            type: .fillSketch,
            operations: sets.flatMap(\.operations),
            path: nil,
            size: nil
        )
    }

    public func fillPolygonSets(points: [[Float]], options: Options) -> [OperationSet] {
        let plan = ContourGeometry.plan(polygon: points, options: options)
        guard !plan.strokes.isEmpty else { return [] }
        if let passes = options.washPasses, !passes.isEmpty {
            return washContour(plan: plan, passes: passes, seed: options.seed ?? passes[0].seed)
        }

        var bands: [Band] = []
        var pieceCount: [Int: Int] = [:]
        for stroke in plan.strokes {
            let piece = pieceCount[stroke.slot, default: 0]
            pieceCount[stroke.slot] = piece + 1
            let quanta = (stroke.scale * 10).rounded() / 10
            if bands.last?.scale != quanta {
                bands.append(Band(scale: quanta, items: []))
            }
            bands[bands.count - 1].items.append((stroke, piece))
        }

        return bands.compactMap { band in
            var operations: [Operation] = []
            for (stroke, piece) in band.items {
                operations.append(contentsOf: roughen(
                    stroke.points,
                    options: options,
                    slot: stroke.slot,
                    piece: piece
                ))
            }
            guard !operations.isEmpty else { return nil }
            return OperationSet(
                type: .fillSketch,
                operations: operations,
                path: nil,
                size: nil,
                fillLineScale: band.scale
            )
        }
    }

    public func fillEllipse(cx: Float, cy: Float, rx: Float, ry: Float, options: Options) -> OperationSet? {
        let sets = fillEllipseSets(cx: cx, cy: cy, rx: rx, ry: ry, options: options)
        guard !sets.isEmpty else { return nil }
        if sets.count == 1 {
            return sets[0]
        }
        return OperationSet(
            type: .fillSketch,
            operations: sets.flatMap(\.operations),
            path: nil,
            size: nil
        )
    }

    public func fillEllipseSets(cx: Float, cy: Float, rx: Float, ry: Float, options: Options) -> [OperationSet] {
        fillPolygonSets(points: ellipsePolygon(cx: cx, cy: cy, rx: rx, ry: ry), options: options)
    }

    /// Strokes each contour centerline with the wash recipe: trim, sine bow, and per-pass width.
    private func washContour(plan: ContourPlan, passes: [WashPass], seed: UInt64) -> [OperationSet] {
        var sets: [OperationSet] = []
        for pass in passes {
            var random = WashRandom(seed: ContourField.mix(seed, Int(pass.seed & 0x7fff_ffff)))
            var operations: [Operation] = []
            for stroke in plan.strokes {
                let trimA = pass.trimMax * (0.35 + 0.65 * random.unit())
                let trimB = pass.trimMax * (0.35 + 0.65 * random.unit())
                let bow = (random.unit() - 0.5) * min(pass.bow, 8)
                let shaped = WashStrokeBuilder.shape(
                    stroke.points,
                    trimStart: trimA,
                    trimEnd: trimB,
                    bow: bow
                )
                guard shaped.count >= 2 else { continue }
                let slotSeed = ContourField.mix(ContourField.mix(seed, stroke.slot), Int(pass.seed & 0x7fff_ffff))
                operations.append(contentsOf: WashStrokeBuilder.operations(
                    points: shaped,
                    seed: slotSeed,
                    pass: pass
                ))
            }
            guard !operations.isEmpty else { continue }
            let width = pass.widthMin + pass.widthSpan * 0.5
            sets.append(OperationSet(
                type: .fillSketch,
                operations: operations,
                path: nil,
                size: nil,
                fillLineWidth: width,
                opacityScale: min(1, pass.opacityMin + pass.opacitySpan * 0.5)
            ))
        }
        return sets
    }

    private struct Band {
        var scale: Float
        var items: [(ContourStroke, Int)]
    }

    private func roughen(
        _ points: [ContourPoint],
        options: Options,
        slot: Int,
        piece: Int
    ) -> [Operation] {
        let samples = points.map { [$0.x, $0.y] }
        guard samples.count >= 2 else { return [] }
        guard let seed = options.seed else {
            return RoughMath.curveOps(points: samples, options: options)
        }
        let slotSeed = ContourField.mix(ContourField.mix(seed, slot), piece)
        return RoughRandom.isolated(seed: slotSeed) {
            var copy = options
            copy.seed = slotSeed
            return RoughMath.curveOps(points: samples, options: copy)
        }
    }

    private func ellipsePolygon(cx: Float, cy: Float, rx: Float, ry: Float) -> [[Float]] {
        let steps = 80
        return (0..<steps).map { index in
            let angle = Float(index) / Float(steps) * 2 * Float.pi
            return [cx + rx * cos(angle), cy + ry * sin(angle)]
        }
    }
}
