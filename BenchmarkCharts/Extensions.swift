// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa

extension NSBezierPath {
    convenience init(linesBetween points: [CGPoint]) {
        self.init()
        appendLines(between: points)
    }
    
    func appendLines(between points: [CGPoint]) {
        guard !points.isEmpty else { return }
        
        move(to: points[0])
        for point in points.dropFirst() {
            line(to: point)
        }
    }

    func setLineDash(_ dashes: [CGFloat]) {
        setLineDash(dashes, count: dashes.count, phase: 0)
    }

    func stroke(with params: BenchmarkTheme.LineParams) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        
        params.apply(on: self)
        params.color.setStroke()
        if params.shadowRadius > 0 {
            let shadow = NSShadow()
            shadow.shadowBlurRadius = params.shadowRadius
            shadow.shadowOffset = .zero
            shadow.shadowColor = .black
            shadow.set()
        }
        stroke()
    }
}

extension Array {
    func looped() -> AnyIterator<Element> {
        var i = 0
        return AnyIterator {
            defer { i = (i + 1 == self.count ? 0 : i + 1) }
            return self[i]
        }
    }

    func repeated(_ count: Int) -> [Element] {
        precondition(count >= 0)
        var result: [Element] = []
        result.reserveCapacity(self.count * count)
        for _ in 0 ..< count {
            result += self
        }
        return result
    }
}
