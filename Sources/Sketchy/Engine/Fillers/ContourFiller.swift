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
