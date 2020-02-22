// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation
import Combine

//extension Dictionary where Value: AnyObject {
//    mutating func value(for key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
//        if let value = self[key] { return value }
//        let value = defaultValue()
//        self[key] = value
//        return value
//    }
//}

public class Attaresult: NSObject, Codable {
    
    /// URL of the .attabench document.
    public let benchmarkURL = CurrentValueSubject<URL?, Never>(nil)

    public let benchmarkDisplayNameSubject = CurrentValueSubject<String, Never>("Benchmark")
    public private(set) lazy var benchmarkDisplayName: AnyPublisher<String, Never> = {
        benchmarkURL
            .map { url in
                guard let url = url else { return "Benchmark" }
                return FileManager.default.displayName(atPath: url.path)
            }
            .eraseToAnyPublisher()
    }()
//    public private(set) lazy var benchmarkDisplayName: AnyObservableValue<String>
//        = benchmarkURL.map { url in
//            guard let url = url else { return "Benchmark" }
//            return FileManager.default.displayName(atPath: url.path)
//    }.buffered()

    // Data

    public let tasks = CurrentValueSubject<[Task], Never>([])
    private var tasksByName: [String: Task] = [:]
//    private lazy var tasksByName: [String: Task] = {
//        var d = [String: Task](uniqueKeysWithValues: self.tasks.value.map { ($0.name, $0) })
//        self.glue.connector.connect(tasks.updates) { [unowned self] update in
//            guard case let .change(change) = update else { return }
//            change.forEachOld { task in self.tasksByName.removeValue(forKey: task.name) }
//            change.forEachNew { task in self.tasksByName[task.name] = task }
//        }
//        return d
//    }()

//    public private(set) lazy var newMeasurements: AnySource<(size: Int, time: Time)>
//        = self.tasks.map { $0.newMeasurements }.gather()
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

    public static let largestPossibleSizeScale: Int = 32
    public static let sizeScaleLimits: ClosedRange<Int> = 0 ... 32

    public static let timeScaleLimits: ClosedRange<Time>
        = Time(picoseconds: 1) ... Time(1_000_000.0)

    public let iterations = CurrentValueSubject<Int, Never>(3)
    public let durationRange = ClosedRangeVar<Time>(0.01 ... 10.0, limits: Attaresult.timeScaleLimits)

    public let sizeScaleRange = ClosedRangeVar<Int>(0 ... 20, limits: Attaresult.sizeScaleLimits)
    public let sizeSubdivisions = CurrentValueSubject<Int, Never>(8)

    public let selectedSizesSubject = CurrentValueSubject<Set<Int>, Never>([])
    public private(set) lazy var selectedSizes: AnyPublisher<Set<Int>, Never> = {
        return sizeSubdivisions.combineLatest(sizeScaleRange.valuePublisher) { subs, range in
            let lower = max(0, min(Attaresult.largestPossibleSizeScale, range.lowerBound))
            let upper = max(0, min(Attaresult.largestPossibleSizeScale, range.upperBound))
            var sizes: Set<Int> = []
            for i in subs * lower ... subs * upper {
                let size = exp2(Double(i) / Double(subs))
                sizes.insert(Int(size))
            }
            return sizes
        }.eraseToAnyPublisher()
    }()
    
    public let selectedSizeRangeSubject = CurrentValueSubject<ClosedRange<Int>, Never>(0...0)
    public private(set) lazy var selectedSizeRange: AnyPublisher<ClosedRange<Int>, Never> = {
        sizeScaleRange.valuePublisher
            .map({ (1 << $0.lowerBound) ... (1 << $0.upperBound) })
            .eraseToAnyPublisher()
    }()

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

    public let displaySizeScaleRange = ClosedRangeVar<Int>(0 ... 20, limits: Attaresult.sizeScaleLimits)
    public let displayIncludeSizeScaleRange = CurrentValueSubject<Bool, Never>(false)
    public let displayIncludeAllMeasuredSizes = CurrentValueSubject<Bool, Never>(true)

    public let displayTimeRange = ClosedRangeVar<Time>(Time.nanosecond ... Time.second, limits: Attaresult.timeScaleLimits)
    public let displayIncludeTimeRange = CurrentValueSubject<Bool, Never>(false)
    public let displayIncludeAllMeasuredTimes = CurrentValueSubject<Bool, Never>(true)

    public let themeName = CurrentValueSubject<String, Never>("")
    public let progressRefreshInterval = CurrentValueSubject<Time, Never>(0.2)
    public let chartRefreshInterval = CurrentValueSubject<Time, Never>(0.5)

    public private(set) lazy var chartOptionsTick: AnyPublisher<Void, Never> = {
        return Publishers.MergeMany([
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
        ]).eraseToAnyPublisher()
    }()

    public override init() {
        super.init()
        privateInit()
    }
    
    var cancellables = Set<AnyCancellable>()
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
            .subscribe(benchmarkDisplayNameSubject)
            .store(in: &cancellables)
        
        
        sizeSubdivisions
            .combineLatest(sizeScaleRange.valuePublisher) { subs, range in
                let lower = max(0, min(Attaresult.largestPossibleSizeScale, range.lowerBound))
                let upper = max(0, min(Attaresult.largestPossibleSizeScale, range.upperBound))
                var sizes: Set<Int> = []
                for i in subs * lower ... subs * upper {
                    let size = exp2(Double(i) / Double(subs))
                    sizes.insert(Int(size))
                }
                return sizes
            }
            .subscribe(selectedSizesSubject)
            .store(in: &cancellables)
        
        sizeScaleRange.valuePublisher
            .map({ (1 << $0.lowerBound) ... (1 << $0.upperBound) })
            .subscribe(selectedSizeRangeSubject)
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

    public required init(from decoder: Decoder) throws {
        super.init()
        
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

    // MARK: Measurements

    public func remove(_ task: Task) {
        let i = tasks.value.firstIndex(of: task)!
        tasks.value.remove(at: i)
        tasksByName.removeValue(forKey: task.name)
    }
    public func task(for name: String) -> Task {
        if let task = self.tasksByName[name] {
            return task
        }
        let task = Task(name: name)
        tasks.value.append(task)
        return self.tasksByName[name]!
    }
    public func task(named name: String) -> Task? {
        return tasksByName[name]
    }

    public func addMeasurement(_ time: Time, forTask taskName: String, size: Int) {
        let task = self.task(for: taskName)
        task.addMeasurement(time, forSize: size)
    }

    public typealias Band = TimeSample.Band

    public func bounds(for band: Band, tasks: [Task]? = nil, amortized: Bool) -> (size: Bounds<Int>, time: Bounds<Time>) {
        var sizeBounds = Bounds<Int>()
        var timeBounds = Bounds<Time>()
        for task in tasks ?? self.tasks.value {
            let b = task.bounds(for: band, amortized: amortized)
            sizeBounds.formUnion(with: b.size)
            timeBounds.formUnion(with: b.time)
        }
        return (sizeBounds, timeBounds)
    }
}

