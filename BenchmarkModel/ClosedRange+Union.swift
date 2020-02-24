//
//  ClosedRange+Union.swift
//  BenchmarkModel
//
//  Created by Evgeny Kazakov on 2/24/20.
//  Copyright © 2020 Károly Lőrentey. All rights reserved.
//

extension ClosedRange {
    public func union(_ other: ClosedRange<Bound>) -> ClosedRange<Bound> {
        Swift.min(lowerBound, other.lowerBound) ... Swift.max(upperBound, other.upperBound)
    }

    public func union<S: Sequence>(_ otherBounds: S) -> ClosedRange<Bound> where S.Element == ClosedRange<Bound> {
        otherBounds.reduce(self) { acc, bounds in acc.union(bounds) }
    }
}
