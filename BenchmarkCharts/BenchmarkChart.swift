//
//  ChartRendering.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-01-20.
//  Copyright © 2017 Károly Lőrentey.
//

import Cocoa
import BenchmarkModel

public enum BandIndex: CaseIterable {
    case top
    case center
    case bottom
}

struct Curve {
    var title: String
    var band: [BandIndex: [CGPoint]] = [:]

    subscript(_ bandIndex: BandIndex) -> [CGPoint] {
        get { band[bandIndex, default: []] }
        set { band[bandIndex] = newValue }
    }
}

struct RawCurve {
    struct Sample {
        let size: Int
        let time: Time
    }
    var title: String
    var band: [BandIndex: [Sample]] = [:]

    subscript(_ bandIndex: BandIndex) -> [Sample] {
        get { band[bandIndex, default: []] }
        set { band[bandIndex] = newValue }
    }

    mutating func append(_ sample: Sample, at bandIndex: BandIndex) {
        self[bandIndex].append(sample)
    }
}

/// Contains a preprocessed copy of selected data from a bunch of benchmark results, according to given parameters.
public struct BenchmarkChart {
    public typealias Band = TimeSample.Band

    public struct Options {
        public var amortizedTime = true
        public var logarithmicTime = true
        public var logarithmicSize = true
        public var band: [BandIndex: Band] = [.center: .average]

        public var displaySizeRange: ClosedRange<Int>? = nil
        public var displayAllMeasuredSizes = true

        public var displayTimeRange: ClosedRange<Time>? = nil
        public var displayAllMeasuredTimes = true

        public init() {}
        
        subscript(_ bandIndex: BandIndex) -> Band? {
            get { band[bandIndex] }
            set { band[bandIndex] = newValue }
        }
    }

    public let title: String
    public let tasks: [String]
    public let options: Options
    let curves: [Curve]
    let sizeScale: ChartScale
    let timeScale: ChartScale

    public init(title: String,
                tasks: [Task],
                options: Options) {
        self.title = title
        self.tasks = tasks.map { $0.name }
        self.options = options

        var minSize = options.displaySizeRange?.lowerBound
        var maxSize = options.displaySizeRange?.upperBound
        var minTime = options.displayTimeRange?.lowerBound
        var maxTime = options.displayTimeRange?.upperBound

        // Gather data.
        var rawCurves: [RawCurve] = []
        for task in tasks {
            var rawCurve = RawCurve(title: task.name)
            for (size, sample) in task.samples.sorted(by: { $0.key < $1.key }) {
                for bandIndex in BandIndex.allCases {
                    guard let band = options[bandIndex] else { continue }
                    guard let time = sample[band] else { continue }
                    let t = options.amortizedTime ? time / size : time
                    rawCurve.append(.init(size: size, time: t), at: bandIndex)
                    if options.displayAllMeasuredSizes {
                        minSize = min(minSize, size)
                        maxSize = max(maxSize, size)
                    }
                    if options.displayAllMeasuredTimes {
                        minTime = min(minTime, t)
                        maxTime = max(maxTime, t)
                    }
                }
            }
            rawCurves.append(rawCurve)
        }

        // Set up horizontal and vertical scales.
        if let minSize = minSize, let maxSize = maxSize {
            let xrange = Double(minSize) ... Double(maxSize)
            if options.logarithmicSize {
                let labeler: (Int) -> String = { value in (1 << value).sizeLabel }
                sizeScale = LogarithmicScale(xrange, decimal: false, labeler: labeler)
            } else {
                let labeler: (Double) -> String = { value in Int(value).sizeLabel }
                sizeScale = LinearScale(xrange, decimal: false, labeler: labeler)
            }
        } else {
            sizeScale = EmptyScale()
        }

        if let minTime = minTime, let maxTime = maxTime {
            let yrange = minTime.seconds ... maxTime.seconds
            if options.logarithmicTime {
                let labeler: (Int) -> String = { value in "\(Time(orderOfMagnitude: value))" }
                timeScale = LogarithmicScale(yrange, decimal: true, labeler: labeler)
            } else {
                let labeler: (Double) -> String = { value in "\(Time(value))" }
                timeScale = LinearScale(yrange, decimal: true, labeler: labeler)
            }
        } else {
            // Empty chart.
            timeScale = EmptyScale()
        }

        // Calculate curves.
        let transform: (RawCurve.Sample) -> CGPoint = { [sizeScale, timeScale] sample in
            CGPoint(x: sizeScale.position(for: Double(sample.size)),
                    y: timeScale.position(for: sample.time.seconds))
        }
        
        curves = rawCurves.map { raw in
            Curve(
                title: raw.title,
                band: raw.band.mapValues { $0.map(transform) }
            )
        }
    }
}

extension BenchmarkChart: CustomPlaygroundDisplayConvertible {
    public var playgroundDescription: Any {
        var options = BenchmarkRenderer.Options()
        options.showTitle = true
        options.legendPosition = .topLeft
        options.legendHorizontalMargin = 32
        options.legendVerticalMargin = 32
        let rect = CGRect(x: 0, y: 0, width: 1024, height: 640)
        let theme = BenchmarkTheme.Predefined.screen
        let renderer = BenchmarkRenderer(chart: self, theme: theme, options: options, in: rect)
        return renderer.image
    }
}

private func min<C: Comparable>(_ a: C?, _ b: C?) -> C? {
    switch (a, b) {
    case let (a?, b?): return Swift.min(a, b)
    case let (a?, nil): return a
    case let (nil, b?): return b
    case (nil, nil): return nil
    }
}

private func max<C: Comparable>(_ a: C?, _ b: C?) -> C? {
    switch (a, b) {
    case let (a?, b?): return Swift.max(a, b)
    case let (a?, nil): return a
    case let (nil, b?): return b
    case (nil, nil): return nil
    }
}
