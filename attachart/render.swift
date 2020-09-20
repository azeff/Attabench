// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import ArgumentParser
import BenchmarkCharts
import BenchmarkModel
import Foundation

func render(_ inputURL: URL, to outputURL: URL, with options: Options) throws {
    let data = try Data(contentsOf: inputURL)
    let model = try JSONDecoder().decode(Attaresult.self, from: data)
    try render(model: model, to: outputURL, with: options)
}

private func render(model: Attaresult, to outputURL: URL, with options: Options) throws {
    let tasks: [Task]
    if options.tasks.isEmpty {
        tasks = model.tasks.value
    } else {
        tasks = try options.tasks.map { name -> Task in
            guard let task = model.task(named: name) else {
                throw ValidationError("Unknown task '\(name)'")
            }
            return task
        }
    }

    let chart = BenchmarkChart(title: options.title ?? "", tasks: tasks, options: options.asChartOptions)
    let theme = try getTheme(for: options)
    
    let imageSize: CGSize
    if let (width, height) = options.size {
        imageSize = CGSize(width: width, height: height)
    } else {
        guard let size = theme.imageSize else {
            throw ValidationError("Please select a theme with a predefined image size or specify an explicit size")
        }
        imageSize = size
    }

    var renderOptions = BenchmarkRenderer.Options()
    renderOptions.showTitle = !chart.title.isEmpty
    renderOptions.legendHorizontalMargin = 0.04 * min(imageSize.width, imageSize.height)
    renderOptions.legendVerticalMargin = renderOptions.legendHorizontalMargin

    let renderer = BenchmarkRenderer(
        chart: chart,
        theme: theme,
        options: renderOptions,
        in: CGRect(origin: .zero, size: imageSize)
    )

    let image = renderer.image

    switch outputURL.pathExtension.lowercased() {
    case "png":
        try image.pngData(scale: options.scale).write(to: outputURL)
    case "pdf":
        try image.pdfData().write(to: outputURL)
    default:
        throw ValidationError("Unknown file extension '\(outputURL.pathExtension)'; expected .png or .pdf")
    }
}

extension Options {
    var asChartOptions: BenchmarkChart.Options {
        var chartOptions = BenchmarkChart.Options()
        chartOptions.amortizedTime = amortized
        chartOptions.logarithmicTime = logarithmicTime
        chartOptions.logarithmicSize = logarithmicSize
        chartOptions.band[.top] = topBand.value
        chartOptions.band[.center] = centerBand.value
        chartOptions.band[.bottom] = bottomBand.value
        if let (minSize, maxSize) = inputSize {
            chartOptions.displaySizeRange = minSize ... maxSize
            chartOptions.displayAllMeasuredSizes = false
        } else {
            chartOptions.displayAllMeasuredSizes = true
        }

        if let (minTime, maxTime) = time {
            chartOptions.displayTimeRange = minTime ... maxTime
            chartOptions.displayAllMeasuredTimes = false
        } else {
            chartOptions.displayAllMeasuredTimes = true
        }
        return chartOptions
    }
}

private func getTheme(for options: Options) throws -> BenchmarkTheme {
    let themeName = options.theme.name
    guard var theme = BenchmarkTheme.Predefined.theme(named: themeName) else {
        throw ValidationError("Unknown theme '\(themeName); use -list-themes to get a list of available themes")
    }

    if let fontName = options.axisFontName {
        theme.setLabelFontName(fontName)
    }
    if let fontName = options.legendFontName {
        theme.setLegendFontName(fontName)
    }
    if !options.branding {
        theme.branding = nil
    }
    return theme
}

extension Options.Theme {
    var name: String {
        switch self {
        case .screen: return "Screen"
        case .presentation: return "Presentation"
        case .colorPrint: return "Color Print"
        case .monochromePrint: return "Monochrome Print"
        }
    }
}

extension Options.Band {
    var value: TimeSample.Band? {
        switch self {
        case .off: return nil
        case .average: return .average
        case .minimum: return .minimum
        case .maximum: return .maximum
        case .sigma1: return .sigma(1)
        case .sigma2: return .sigma(2)
        case .sigma3: return .sigma(3)
        }
    }
}
