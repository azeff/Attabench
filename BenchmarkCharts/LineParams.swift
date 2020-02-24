// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa

extension BenchmarkTheme {
    public struct LineParams {
        public let lineWidth: CGFloat
        public let color: NSColor
        public let dash: [CGFloat]
        public let phase: CGFloat
        public let capStyle: NSBezierPath.LineCapStyle
        public let joinStyle: NSBezierPath.LineJoinStyle
        public let shadowRadius: CGFloat

        public init(
            lineWidth: CGFloat,
            color: NSColor,
            dash: [CGFloat] = [],
            phase: CGFloat = 0,
            capStyle: NSBezierPath.LineCapStyle = .round,
            joinStyle: NSBezierPath.LineJoinStyle = .round,
            shadowRadius: CGFloat = 0
        ) {
            self.lineWidth = lineWidth
            self.color = color
            self.dash = dash
            self.phase = phase
            self.capStyle = capStyle
            self.joinStyle = joinStyle
            self.shadowRadius = shadowRadius
        }

        public func apply(on path: NSBezierPath) {
            path.lineWidth = lineWidth
            path.lineJoinStyle = joinStyle
            path.lineCapStyle = capStyle
            path.setLineDash(dash)
        }
    }
}
