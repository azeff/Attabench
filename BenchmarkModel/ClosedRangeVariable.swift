// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Combine

public class ClosedRangeVariable<Bounds: Comparable> {
    
    public var value: ClosedRange<Bounds> {
        get { valueSubject.value }
        set { valueSubject.value = newValue }
    }
    
    public var lowerBound: Bounds {
        get { value.lowerBound }
        set { valueSubject.value = newValue ... value.upperBound }
    }
    
    public var upperBound: Bounds  {
        get { value.upperBound }
        set { valueSubject.value = value.lowerBound ... newValue }
    }

    public let valuePublisher: AnyPublisher<ClosedRange<Bounds>, Never>
    public let lowerBoundPublisher: AnyPublisher<Bounds, Never>
    public let upperBoundPublisher: AnyPublisher<Bounds, Never>

    private let valueSubject: CurrentValueSubject<ClosedRange<Bounds>, Never>
    
    init(_ value: ClosedRange<Bounds>, limits: ClosedRange<Bounds>? = nil) {
        self.valueSubject = CurrentValueSubject(value)
        self.valuePublisher = valueSubject.eraseToAnyPublisher()
        lowerBoundPublisher = self.valueSubject.map(\.lowerBound).eraseToAnyPublisher()
        upperBoundPublisher = self.valueSubject.map(\.upperBound).eraseToAnyPublisher()
    }
    
    public func updateLowerBound(_ lowerBound: Bounds) {
        valueSubject.value = lowerBound ... valueSubject.value.upperBound
    }
    
    public func updateUpperBound(_ upperBound: Bounds) {
        valueSubject.value = valueSubject.value.lowerBound ... upperBound
    }
}
