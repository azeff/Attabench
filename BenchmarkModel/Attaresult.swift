// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation
import Combine

public class Attaresult: Codable {
    
    public typealias Band = TimeSample.Band
    
    /// URL of the .attabench document.
    public let benchmarkURL = CurrentValueSubject<URL?, Never>(nil)

    public let benchmarkDisplayName = CurrentValueSubject<String, Never>("Benchmark")

    // Data

    public let tasks = CurrentValueSubject<[Task], Never>([])
    private var tasksByName: [String: Task] = [:]

    public private(set) lazy var newMeasurements: AnyPublisher<(size: Int, time: Time), Never> = {
        return tasks
            .map({ tasks -> AnyPublisher<(size: Int, time: Time), Never> in
                let subjects = tasks.map({ $0.newMeasurements })
                return Publishers.MergeMany(subjects).eraseToAnyPublisher()
            })
            .switchToLatest()
            .eraseToAnyPublisher()
    }()

    // Run options

    public static let largestPossibleSizeScale = 32
    public static let sizeScaleLimits = 0 ... 32
    public static let timeScaleLimits = Time(picoseconds: 1) ... Time(1_000_000.0)

    public let iterations = CurrentValueSubject<Int, Never>(3)
    public let durationRange = ClosedRangeVariable<Time>(0.01 ... 10.0, limits: Attaresult.timeScaleLimits)

    public let sizeScaleRange = ClosedRangeVariable<Int>(0 ... 20, limits: Attaresult.sizeScaleLimits)
    public let sizeSubdivisions = CurrentValueSubject<Int, Never>(8)

    public let selectedSizes = CurrentValueSubject<Set<Int>, Never>([])    
    public let selectedSizeRange = CurrentValueSubject<ClosedRange<Int>, Never>(0...0)

    public private(set) lazy var runOptionsTick: AnyPublisher<Void, Never> = {
        Publishers.Merge4(
            iterations.map({ _ in Void() }),
            durationRange.valuePublisher.map({ _ in Void() }),
            sizeScaleRange.valuePublisher.map({ _ in Void() }),
            sizeSubdivisions.map({ _ in Void() })
        ).eraseToAnyPublisher()
    }()

    // Chart options

    public let amortizedTime = CurrentValueSubject<Bool, Never>(true)
    public let logarithmicSizeScale = CurrentValueSubject<Bool, Never>(true)
    public let logarithmicTimeScale = CurrentValueSubject<Bool, Never>(true)

    public let topBand = CurrentValueSubject<Band, Never>(.sigma(2))
    public let centerBand = CurrentValueSubject<Band, Never>(.average)
    public let bottomBand = CurrentValueSubject<Band, Never>(.minimum)

    public let highlightSelectedSizeRange = CurrentValueSubject<Bool, Never>(true)

    public let displaySizeScaleRange = ClosedRangeVariable<Int>(0 ... 20, limits: Attaresult.sizeScaleLimits)
    public let displayIncludeSizeScaleRange = CurrentValueSubject<Bool, Never>(false)
    public let displayIncludeAllMeasuredSizes = CurrentValueSubject<Bool, Never>(true)

    public let displayTimeRange = ClosedRangeVariable<Time>(Time.nanosecond ... Time.second, limits: Attaresult.timeScaleLimits)
    public let displayIncludeTimeRange = CurrentValueSubject<Bool, Never>(false)
    public let displayIncludeAllMeasuredTimes = CurrentValueSubject<Bool, Never>(true)

    public let themeName = CurrentValueSubject<String, Never>("")
    public let progressRefreshInterval = CurrentValueSubject<Time, Never>(0.2)
    public let chartRefreshInterval = CurrentValueSubject<Time, Never>(0.5)

    public private(set) lazy var chartOptionsTick: AnyPublisher<Void, Never> = {
        let publishers: [AnyPublisher<Void, Never>] = [
            amortizedTime.map({ _ in Void() }).eraseToAnyPublisher(),
            logarithmicSizeScale.map({ _ in Void() }).eraseToAnyPublisher(),
            logarithmicTimeScale.map({ _ in Void() }).eraseToAnyPublisher(),
            topBand.map({ _ in Void() }).eraseToAnyPublisher(),
            centerBand.map({ _ in Void() }).eraseToAnyPublisher(),
            centerBand.map({ _ in Void() }).eraseToAnyPublisher(),
            bottomBand.map({ _ in Void() }).eraseToAnyPublisher(),
            highlightSelectedSizeRange.map({ _ in Void() }).eraseToAnyPublisher(),
            displaySizeScaleRange.valuePublisher.map({ _ in Void() }).eraseToAnyPublisher(),
            displayIncludeSizeScaleRange.map({ _ in Void() }).eraseToAnyPublisher(),
            displayIncludeAllMeasuredSizes.map({ _ in Void() }).eraseToAnyPublisher(),
            displayTimeRange.valuePublisher.map({ _ in Void() }).eraseToAnyPublisher(),
            displayIncludeTimeRange.map({ _ in Void() }).eraseToAnyPublisher(),
            displayIncludeAllMeasuredTimes.map({ _ in Void() }).eraseToAnyPublisher(),
            themeName.map({ _ in Void() }).eraseToAnyPublisher(),
            progressRefreshInterval.map({ _ in Void() }).eraseToAnyPublisher(),
            chartRefreshInterval.map({ _ in Void() }).eraseToAnyPublisher()
        ]
        
        return Publishers.MergeMany(publishers).eraseToAnyPublisher()
    }()

    private var cancellables = Set<AnyCancellable>()

    public init() {
        privateInit()
    }
    
    private func privateInit() {
        tasks.sink { [unowned self] tasks in
            self.tasksByName = [String: Task].init(uniqueKeysWithValues: tasks.map({ ($0.name, $0) }))
        }
        .store(in: &cancellables)
        
        benchmarkURL
            .map { url in
                guard let url = url else { return "Benchmark" }
                return FileManager.default.displayName(atPath: url.path)
            }
            .subscribe(benchmarkDisplayName)
            .store(in: &cancellables)
        
        let sizeScaleClamped = sizeScaleRange.valuePublisher
            .map { $0.clamped(to: 0 ... Attaresult.largestPossibleSizeScale) }
        sizeSubdivisions
            .combineLatest(sizeScaleClamped) { subs, range in
                let subsRange = subs * range.lowerBound ... subs * range.upperBound
                let sizes = Set(subsRange.map { Int(exp2(Double($0) / Double(subs))) })
                return sizes
            }
            .subscribe(selectedSizes)
            .store(in: &cancellables)
        
        sizeScaleRange.valuePublisher
            .map({ (1 << $0.lowerBound) ... (1 << $0.upperBound) })
            .subscribe(selectedSizeRange)
            .store(in: &cancellables)
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case taskNames
        case results

        case source
        case tasks
        case iterations
        case minimumDuration
        case maximumDuration
        case minimumSizeScale
        case maximumSizeScale
        case sizeSubdivisions

        case amortizedTime
        case logarithmicSizeScale
        case logarithmicTimeScale
        case topBand
        case centerBand
        case bottomBand
        case highlightSelectedSizeRange
        case displaySizeScaleRangeMin
        case displaySizeScaleRangeMax
        case displayIncludeSizeScaleRange
        case displayIncludeAllMeasuredSizes
        case displayTimeRangeMin
        case displayTimeRangeMax
        case displayIncludeTimeRange
        case displayIncludeAllMeasuredTimes
        case themeName
        case progressRefreshInterval
        case chartRefreshInterval
    }

    public required init(from decoder: Decoder) throws {
        privateInit()
        
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let bookmarkData = try container.decodeIfPresent(Data.self, forKey: .source) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                self.benchmarkURL.value = url
            }
        }

        self.tasks.value = try container.decode([Task].self, forKey: .tasks)
        
        if let v = try container.decodeIfPresent(Int.self, forKey: .iterations) {
            self.iterations.value = v
        }
        if let lower = try container.decodeIfPresent(Double.self, forKey: .minimumDuration),
            let upper = try container.decodeIfPresent(Double.self, forKey: .maximumDuration) {
            self.durationRange.value = (Time(Swift.min(lower, upper)) ... Time(Swift.max(lower, upper)))
                .clamped(to: Attaresult.timeScaleLimits)
        }
        if let lower = try container.decodeIfPresent(Int.self, forKey: .minimumSizeScale),
            let upper = try container.decodeIfPresent(Int.self, forKey: .maximumSizeScale) {
            self.sizeScaleRange.value = (Swift.min(lower, upper) ... Swift.max(lower, upper))
                .clamped(to: Attaresult.sizeScaleLimits)
        }
        if let v = try container.decodeIfPresent(Int.self, forKey: .sizeSubdivisions) {
            self.sizeSubdivisions.value = v
        }

        if let v = try container.decodeIfPresent(Bool.self, forKey: .amortizedTime) {
            self.amortizedTime.value = v
        }
        if let v = try container.decodeIfPresent(Bool.self, forKey: .logarithmicSizeScale) {
            self.logarithmicSizeScale.value = v
        }
        if let v = try container.decodeIfPresent(Bool.self, forKey: .logarithmicTimeScale) {
            self.logarithmicTimeScale.value = v
        }
        if let v = try container.decodeIfPresent(Band.self, forKey: .topBand) {
            self.topBand.value = v
        }
        if let v = try container.decodeIfPresent(Band.self, forKey: .centerBand) {
            self.centerBand.value = v
        }
        if let v = try container.decodeIfPresent(Band.self, forKey: .bottomBand) {
            self.bottomBand.value = v
        }
        if let v = try container.decodeIfPresent(Bool.self, forKey: .highlightSelectedSizeRange) {
            self.highlightSelectedSizeRange.value = v
        }

        if let lower = try container.decodeIfPresent(Int.self, forKey: .displaySizeScaleRangeMin),
            let upper = try container.decodeIfPresent(Int.self, forKey: .displaySizeScaleRangeMax) {
            self.displaySizeScaleRange.value = (Swift.min(lower, upper) ... Swift.max(lower, upper))
                .clamped(to: Attaresult.sizeScaleLimits)
        }
        self.displayIncludeSizeScaleRange.value = try container.decodeIfPresent(Bool.self, forKey: .displayIncludeSizeScaleRange) ?? false
        self.displayIncludeAllMeasuredSizes.value = try container.decodeIfPresent(Bool.self, forKey: .displayIncludeAllMeasuredSizes) ?? true

        if let lower = try container.decodeIfPresent(Double.self, forKey: .displayTimeRangeMin),
            let upper = try container.decodeIfPresent(Double.self, forKey: .displayTimeRangeMax) {
            self.displayTimeRange.value = (Time(Swift.min(lower, upper)) ... Time(Swift.max(lower, upper)))
                .clamped(to: Attaresult.timeScaleLimits)
        }
        self.displayIncludeTimeRange.value = try container.decodeIfPresent(Bool.self, forKey: .displayIncludeTimeRange) ?? false
        self.displayIncludeAllMeasuredTimes.value = try container.decodeIfPresent(Bool.self, forKey: .displayIncludeAllMeasuredTimes) ?? true

        if let v = try container.decodeIfPresent(String.self, forKey: .themeName) {
            self.themeName.value = v
        }
        if let v = try container.decodeIfPresent(Time.self, forKey: .progressRefreshInterval) {
            self.progressRefreshInterval.value = v
        }
        if let v = try container.decodeIfPresent(Time.self, forKey: .chartRefreshInterval) {
            self.chartRefreshInterval.value = v
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let url = self.benchmarkURL.value {
            try container.encode(url.bookmarkData(options: .suitableForBookmarkFile), forKey: .source)
        }
        try container.encode(self.tasks.value, forKey: .tasks)
        try container.encode(self.iterations.value, forKey: .iterations)
        try container.encode(self.durationRange.lowerBound.seconds, forKey: .minimumDuration)
        try container.encode(self.durationRange.upperBound.seconds, forKey: .maximumDuration)
        try container.encode(self.sizeScaleRange.lowerBound, forKey: .minimumSizeScale)
        try container.encode(self.sizeScaleRange.upperBound, forKey: .maximumSizeScale)
        try container.encode(self.sizeSubdivisions.value, forKey: .sizeSubdivisions)
        try container.encode(self.amortizedTime.value, forKey: .amortizedTime)
        try container.encode(self.logarithmicSizeScale.value, forKey: .logarithmicSizeScale)
        try container.encode(self.logarithmicTimeScale.value, forKey: .logarithmicTimeScale)
        try container.encode(self.topBand.value, forKey: .topBand)
        try container.encode(self.centerBand.value, forKey: .centerBand)
        try container.encode(self.bottomBand.value, forKey: .bottomBand)
        try container.encode(self.highlightSelectedSizeRange.value, forKey: .highlightSelectedSizeRange)

        try container.encode(self.displaySizeScaleRange.lowerBound, forKey: .displaySizeScaleRangeMin)
        try container.encode(self.displaySizeScaleRange.upperBound, forKey: .displaySizeScaleRangeMax)
        try container.encode(self.displayIncludeSizeScaleRange.value, forKey: .displayIncludeSizeScaleRange)
        try container.encode(self.displayIncludeAllMeasuredSizes.value, forKey: .displayIncludeAllMeasuredSizes)

        try container.encode(self.displayTimeRange.lowerBound.seconds, forKey: .displayTimeRangeMin)
        try container.encode(self.displayTimeRange.upperBound.seconds, forKey: .displayTimeRangeMax)
        try container.encode(self.displayIncludeTimeRange.value, forKey: .displayIncludeTimeRange)
        try container.encode(self.displayIncludeAllMeasuredTimes.value, forKey: .displayIncludeAllMeasuredTimes)

        try container.encode(self.themeName.value, forKey: .themeName)
        try container.encode(self.progressRefreshInterval.value, forKey: .progressRefreshInterval)
        try container.encode(self.chartRefreshInterval.value, forKey: .chartRefreshInterval)
    }
    
    // MARK: Measurements

    public func remove(_ task: Task) {
        guard let index = tasks.value.firstIndex(of: task) else {
            assertionFailure("Unknown task")
            return
        }
        tasks.value.remove(at: index)
        // TODO: EK - in task(for:) tasksByName is assumed to be updated once tasks value changes.
        // Why removing task explicitly?
        tasksByName.removeValue(forKey: task.name)
    }
    
    public func task(for name: String) -> Task {
        if let task = tasksByName[name] {
            return task
        }
        tasks.value.append(Task(name: name))
        // TODO: EK - relying on tasksByName getting updated once tasks value changes.
        // Not super obvious peace of code, think of how to make it more unerstandable.
        return tasksByName[name]!
    }
    
    public func task(named name: String) -> Task? {
        return tasksByName[name]
    }

    public func addMeasurement(_ time: Time, forTask taskName: String, size: Int) {
        let task = self.task(for: taskName)
        task.addMeasurement(time, forSize: size)
    }

    public func bounds(for band: Band, tasks: [Task]? = nil, amortized: Bool) -> (size: ClosedRange<Int>, time: ClosedRange<Time>)? {
        let tasks = tasks ?? self.tasks.value

        guard !tasks.isEmpty else { return nil }

        let bounds = tasks.compactMap { $0.bounds(for: band, amortized: amortized) }
        let sizesBounds = bounds.map { $0.0 }
        let timesBounds = bounds.map { $0.1 }

        let sizeBounds = sizesBounds[0].union(sizesBounds[1...])
        let timeBounds = timesBounds[0].union(timesBounds[1...])

        return (sizeBounds, timeBounds)
    }
}
