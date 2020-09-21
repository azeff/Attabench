// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import ArgumentParser
import BenchmarkCharts

struct ListThemesCommand: ParsableCommand {
    
    static var configuration = CommandConfiguration(
        commandName: "list-themes",
        abstract: "List available themes and exit."
    )

    func run() throws {
        for theme in BenchmarkTheme.Predefined.themes {
            print(theme.name)
        }
    }
}
