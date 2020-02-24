//
//  TaskFilter.swift
//  Attabench
//
//  Created by Evgeny Kazakov on 2/24/20.
//  Copyright © 2020 Károly Lőrentey. All rights reserved.
//

import Foundation
import BenchmarkModel

struct TaskFilter {
    
    typealias Pattern = (string: String, isNegative: Bool)
    
    let patterns: [[Pattern]]

    init(_ pattern: String?) {
        self.patterns = (pattern ?? "")
            .lowercased()
            .components(separatedBy: ",")
            .map { (pattern: String) -> [Pattern] in
                pattern
                    .components(separatedBy: .whitespacesAndNewlines)
                    .map { (word: String) -> Pattern in
                        word.hasPrefix("!")
                            ? (string: String(word.dropFirst()), isNegative: true)
                            : (string: word, isNegative: false) }
                    .filter { (pattern: Pattern) -> Bool in !pattern.string.isEmpty }
        }
            .filter { !$0.isEmpty }
    }

    func test(_ task: Task) -> Bool {
        guard !patterns.isEmpty else { return true }
        
        let name = task.name.lowercased()
        return patterns.contains { (conjunctive: [Pattern]) -> Bool in
            !conjunctive.contains { (pattern: Pattern) -> Bool in
                name.contains(pattern.string) == pattern.isNegative
            }
        }
    }
}
