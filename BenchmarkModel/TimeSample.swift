// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation
import BigInt

// TODO: EK - make struct?
public final class TimeSample: Codable {
    
    public private(set) var count: Int
    public private(set) var minimum: Time
    public private(set) var maximum: Time
    public private(set) var sum: Time
    public private(set) var sumSquared: TimeSquared

    enum Key: CodingKey {
        case minimum
        case maximum
        case count
        case sum
        case sumSquared
    }

    public init(time: Time) {
        minimum = time
        maximum = time
        sum = time
        sumSquared = time.squared()
        count = 1
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        self.minimum = try container.decode(Time.self, forKey: .minimum)
        self.maximum = try container.decode(Time.self, forKey: .maximum)
        self.count = try container.decode(Int.self, forKey: .count)
        self.sum = try container.decode(Time.self, forKey: .sum)
        self.sumSquared = try container.decode(TimeSquared.self, forKey: .sumSquared)
        
        guard count > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .count, in: container,
                debugDescription: "negative or empty count")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(minimum, forKey: .minimum)
        try container.encode(maximum, forKey: .maximum)
        try container.encode(count, forKey: .count)
        try container.encode(sum, forKey: .sum)
        try container.encode(sumSquared, forKey: .sumSquared)
    }

    public func addMeasurement(_ elapsedTime: Time) {
        minimum = min(elapsedTime, minimum)
        maximum = max(elapsedTime, maximum)
        sum += elapsedTime
        sumSquared += elapsedTime.squared()
        count += 1
    }

    public func addSample(_ sample: TimeSample) {
        self.minimum = min(self.minimum, sample.minimum)
        self.maximum = max(self.maximum, sample.maximum)
        self.count += sample.count
        self.sum += sample.sum
        self.sumSquared += sample.sumSquared
    }

    public var average: Time? {
        if count == 0 { return nil }
        return sum.dividingWithRounding(by: count)
    }

    public var standardDeviation: Time? {
        if count < 2 { return nil }
        let c = BigInt(count)
        let s2 = (c * sumSquared - sum.squared()).dividingWithRounding(by: c * (c - 1))
        return s2.squareRoot()
    }

    public func bounds(for bands: [Band]) -> ClosedRange<Time>? {
        let times = bands.compactMap { self[$0] }
        guard let lowerBound = times.min(), let upperBound = times.max() else { return nil }
        
        return lowerBound ... upperBound
    }
}

extension TimeSample {
    public enum Band: LosslessStringConvertible, Codable, Equatable {
        case maximum
        case sigma(Int)
        case average
        case minimum
        case count // Fixme this isn't a time

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let band = Band(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid band")
            }
            self = band
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode("\(self)")
        }

        public init?(_ description: String) {
            switch description {
            case "maximum": self = .maximum
            case "minimum": self = .minimum
            case "average": self = .average
            case "count": self = .count
            case _ where description.hasSuffix("sigma"):
                let number = description.dropLast(5)
                guard let s = Int(number, radix: 10) else { return nil }
                self = .sigma(s)
            default:
                return nil
            }
        }

        public var description: String {
            switch self {
            case .maximum: return "maximum"
            case .sigma(let s): return "\(s.magnitude)sigma"
            case .average: return "average"
            case .minimum: return "minimum"
            case .count: return "count"
            }
        }
    }

    public subscript(_ band: Band) -> Time? {
        switch band {
        case .maximum: return maximum
        case .sigma(let count):
            guard let average = self.average else { return nil }
            return average + count * (standardDeviation ?? .zero)
        case .average: return average
        case .minimum: return minimum
        case .count: return Time(Double(count))
        }
    }
}
