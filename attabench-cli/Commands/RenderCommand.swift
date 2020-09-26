// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import ArgumentParser
import BenchmarkCharts
import BenchmarkModel
import Foundation

struct RenderCommand: ParsableCommand {
    
    static var configuration = CommandConfiguration(
        commandName: "render",
        abstract: "Render to file benchmark results chart."
    )

    @Argument(
        help: .init("Path to .attaresult file with benchmark results.", valueName: "input"),
        completion: .file(extensions: ["attaresult"])
    )
    var benchmarkResultFilePath: String
    
    @Option(
        name: [.customShort("o"), .customLong("output")],
        help: .init("Path to output file (PNG or PDF).", valueName: "output"),
        completion: .file(extensions: ["png, pdf"])
    )
    var outputImageFilePath: String

    @Option(
        name: [.short, .long],
        parsing: .upToNextOption,
        help: "Names of tasks to render. Render all tasks if not specified."
    )
    var tasks: [String] = []

    @Option(
        help: "Minimum input size."
    )
    var minSize: Int?
    
    @Option(
        help: "Maximum input size."
    )
    var maxSize: Int?
    
    @Option(
        help: "Minimum time."
    )
    var minTime: Time?
    
    @Option(
        help: "Maximum time."
    )
    var maxTime: Time?
    
    @Flag(
        inversion: .prefixedNo,
        help: "Amortized time."
    )
    var amortizedTime: Bool = true
    
    @Flag(
        inversion: .prefixedNo,
        help: "Logarithmic size scale."
    )
    var logarithmicSize: Bool = true

    @Flag(
        inversion: .prefixedNo,
        help: "Logarithmic time scale."
    )
    var logarithmicTime: Bool = true

    @Option(
        help: .init(
            #"Top band (allowed values: "none", "avg", "min", "max", "sigma1", "sigma2", "sigma3")."#,
            valueName: "band"
        )
    )
    var topBand: RenderOptions.Band = .sigma2
    
    @Option(
        help: .init(
            #"Center band (allowed values: "none", "avg", "min", "max", "sigma1", "sigma2", "sigma3")."#,
            valueName: "band"
        )
    )
    var centerBand: RenderOptions.Band = .average

    @Option(
        help: .init(
            #"Bottom band (allowed values: "none", "avg", "min", "max", "sigma1", "sigma2", "sigma3")."#,
            valueName: "band"
        )
    )
    var bottomBand: RenderOptions.Band = .minimum

    @Option(
        help: "Generate chart with thise theme."
    )
    var theme: RenderOptions.Theme = .screen

    @Option(
        help: "Width of generated image, in points."
    )
    var width: Int?

    @Option(
        help: "Height of generated image, in points."
    )
    var height: Int?
    
    @Option(
        help: "Number of pixels in a point."
    )
    var scale: Int = 1

    @Option(
        help: "Title"
    )
    var title: String?
    
    @Flag(
        help: "Use benchmark result filename as title"
    )
    var filenameAsTitle: Bool = false

    @Option(
        name: .customLong("axis-font"),
        help: .init("Name of a font to use for axis.", valueName: "font")
    )
    var axisFontName: String = "SF Pro Text"
    
    @Option(
        name: .customLong("legend-font"),
        help: .init("Name of a font to use for legend.", valueName: "font")
    )
    var legendFontName: String = "SF Mono"

    @Flag(
        inversion: .prefixedEnableDisable,
        help: "Enable/disable Attabench branding"
    )
    var branding: Bool = true
    
    mutating func validate() throws {
        if (minSize != nil && maxSize == nil) || (minSize == nil && maxSize != nil) {
            throw ValidationError("Both -min-size and -max-size must be specified.")
        }
        if let minSize = minSize, let maxSize = maxSize, maxSize < minSize {
            throw ValidationError("-min-size must be lower than -max-size.")
        }

        if (minTime != nil && maxTime == nil) || (minTime == nil && maxTime != nil) {
            throw ValidationError("Both -min-time and -max-time must be specified.")
        }
        if let minTime = minTime, let maxTime = maxTime, maxTime < minTime {
            throw ValidationError("-min-time must be lower than -max-time.")
        }

        if (width != nil && height == nil) || (width == nil && height != nil) {
            throw ValidationError("Both -width and -height must be specified.")
        }
        
        if BenchmarkTheme.Predefined.theme(named: theme.name) == nil {
            throw ValidationError("Unknown theme '\(theme); use -list-themes to get a list of available themes.")
        }
        
        let outputURL = URL(fileURLWithPath: outputImageFilePath)
        let outputFilenameExtension = outputURL.pathExtension.lowercased()
        if outputFilenameExtension != "png" && outputFilenameExtension != "pdf" {
            throw ValidationError("Unsupported file extension '\(outputURL.pathExtension)'. Allowed file extensions: .png or .pdf.")
        }
    }
    
    func run() throws {
        let inputURL = URL(fileURLWithPath: benchmarkResultFilePath)
        let outputURL = URL(fileURLWithPath: outputImageFilePath)
        try render(inputURL, to: outputURL, with: options)
    }
}

extension RenderCommand {
    var options: RenderOptions {
        let inputSize: (min: Int, max: Int)?
        if let minSize = minSize, let maxSize = maxSize {
            inputSize = (min: minSize, max: maxSize)
        } else {
            inputSize = nil
        }
        
        let time: (min: Time, max: Time)?
        if let minTime = minTime, let maxTime = maxTime {
            time = (min: minTime, max: maxTime)
        } else {
            time = nil
        }

        let size: (width: Int, height: Int)?
        if let width = width, let height = height {
            size = (width: width, height: height)
        } else {
            size = nil
        }
        
        let title: String?
        if filenameAsTitle {
            let inputURL = URL(fileURLWithPath: benchmarkResultFilePath)
            let filename = inputURL.lastPathComponent
            title = filename
        } else {
            title = self.title
        }

        return RenderOptions(
            tasks: tasks,
            inputSize: inputSize,
            time: time,
            amortized: amortizedTime,
            logarithmicSize: logarithmicSize,
            logarithmicTime: logarithmicTime,
            topBand: topBand,
            centerBand: centerBand,
            bottomBand: bottomBand,
            theme: theme,
            size: size,
            scale: scale,
            title: title,
            axisFontName: axisFontName,
            legendFontName: legendFontName,
            branding: branding
        )
    }
}
