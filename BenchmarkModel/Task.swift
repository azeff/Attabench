// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation
import Combine

public final class Task: Codable, Hashable {
    
    public typealias Band = TimeSample.Band

    public let name: String
    public private(set) var samples: [Int: TimeSample] = [:]
    public let checked = CurrentValueSubject<Bool, Never>(true)
    public let isRunnable = CurrentValueSubject<Bool, Never>(false)
    public let sampleCount = CurrentValueSubject<Int, Never>(0)
    public let newMeasurements = PassthroughSubject<(size: Int, time: Time), Never>()

    enum CodingKey: String, Swift.CodingKey {
        case name
        case samples
        case checked
    }

    public init(name: String) {
        self.name = name
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKey.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.samples = try container.decode([Int: TimeSample].self, forKey: .samples)
        self.sampleCount.value = self.samples.values.reduce(0) { $0 + $1.count }
        if let checked = try container.decodeIfPresent(Bool.self, forKey: .checked) {
            self.checked.value = checked
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKey.self)
        try container.encode(self.name, forKey: .name)
        try container.encode(self.samples, forKey: .samples)
        try container.encode(self.checked.value, forKey: .checked)
    }

    public func addMeasurement(_ time: Time, forSize size: Int) {
        let sample = samples[size, default: TimeSample(time: time)]
        sample.addMeasurement(time)
        samples[size] = sample
        newMeasurements.send((size, time))
        sampleCount.value += 1
    }

    public func bounds(for band: Band, amortized: Bool) -> (size: ClosedRange<Int>, time: ClosedRange<Time>)? {
        let bandTimes = samples.compactMapValues({ $0[band] })
        guard !bandTimes.isEmpty else { return nil }

        let times = bandTimes.map { size, time in amortized ? time / size : time }

        let sizeBounds = bandTimes.keys.min()! ... bandTimes.keys.max()!
        let timeBounds = times.min()! ... times.max()!

        return (sizeBounds, timeBounds)
    }
    
    public func deleteResults(in range: ClosedRange<Int>? = nil) {
        if let range = range {
            samples = samples.filter { !range.contains($0.key) }
            sampleCount.value = samples.values.reduce(0) { $0 + $1.count }
        }
        else {
            samples = [:]
            sampleCount.value = 0
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    public static func ==(left: Task, right: Task) -> Bool {
        return left.name == right.name
    }
}
