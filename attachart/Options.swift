// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import BenchmarkModel
import BenchmarkCharts
import ArgumentParser

struct Options {
    
    enum Band: String, ExpressibleByArgument {
        case off = "none"
        case average = "avg"
        case minimum = "min"
        case maximum = "max"
        case sigma1 = "sigma1"
        case sigma2 = "sigma2"
        case sigma3 = "sigma3"
        
        var defaultValueDescription: String {
            rawValue
        }
    }

    enum Theme: String, ExpressibleByArgument {
        case screen
        case presentation
        case colorPrint
        case monochromePrint
    }

    var tasks: [String] = []
    var inputSize: (min: Int, max: Int)?
    var time: (min: Time, max: Time)?
    var amortized = true
    var logarithmicSize = true
    var logarithmicTime = true

    var topBand: Band
    var centerBand: Band
    var bottomBand: Band

    var theme: Theme
    var size: (width: Int, height: Int)?
    var scale: Int
    var title: String?
    var axisFontName: String?
    var legendFontName: String?
    var branding: Bool = false
}

extension Time: ExpressibleByArgument {

    public init?(argument: String) {
        guard let value = Time(argument) else {
            return nil
        }
        self = value
    }
}
