// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import ArgumentParser
import BenchmarkModel
import Foundation

struct ListTasksCommand: ParsableCommand {
   
    static var configuration = CommandConfiguration(
        commandName: "list-tasks",
        abstract: "List available task names in file and exit."
    )
    
    @Argument(help: .init("Path to .attaresult file with benchmark results.", valueName: "path"))
    var benchmarkResultFilePath: String
    
    func run() throws {
        let fileURL = URL(fileURLWithPath: benchmarkResultFilePath)
        let data = try Data(contentsOf: fileURL)
        let model = try JSONDecoder().decode(Attaresult.self, from: data)
        for task in model.tasks.value {
            print(task.name)
        }
    }
}
