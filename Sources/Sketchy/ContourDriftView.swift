//
//  ContourDriftView.swift
//  Sketchy
//
//  Plays a contour fill by sliding a seeded stroke field.
//

import SwiftUI

/// A contour fill whose strokes travel across the shape.
///
/// The phase is `speed` points per second from the moment the view appears.
/// Each frame rebuilds centerlines from the same slot seeds, so the wax does
/// not boil. Build it with `RoughView.animatedContour(angle:speed:)`.
public struct ContourDriftView: View {
    private let base: RoughView
    private let angle: Float
    private let speed: Float
    @State private var start = Date()

    public init(base: RoughView, angle: Float, speed: Float) {
        self.base = base
        self.angle = angle
        self.speed = speed
    }

    public var body: some View {
        TimelineView(.periodic(from: start, by: 1.0 / 30.0)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            base.contourDrift(angle: angle, speed: speed, phase: Float(elapsed) * speed)
        }
    }
}
