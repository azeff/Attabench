// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import Combine
import BenchmarkModel

class TaskCellView: NSTableCellView {
    @IBOutlet weak var checkbox: NSButton?
    @IBOutlet weak var detail: NSTextField?

    weak var context: AttabenchDocument? // FIXME argh

    override func awakeFromNib() {
        self.appearance = NSAppearance(named: .vibrantLight)
    }

    private var cancellables: Set<AnyCancellable> = []
   
    var task: Task? = nil {
        didSet {
            cancellables = []

            if let task = task {
                self.textField?.stringValue = task.name
                task.checked
                    .sink { [unowned self] value in
                        guard let checkbox = self.checkbox else { return }
                        let v: NSControl.StateValue = (value ? .on : .off)
                        if checkbox.state != v {
                            checkbox.state = v
                        }
                    }
                    .store(in: &cancellables)
                task.isRunnable
                    .sink { [unowned self, task] value in
                        guard let label = self.textField else { return }
                        let title = task.name + (value ? "" : " ✖︎")
                        if label.stringValue != title {
                            label.stringValue = title
                        }
                    }
                    .store(in: &cancellables)
                task.sampleCount
                    .sink { [unowned self] value in
                        guard let detail = self.detail else { return }
                        detail.stringValue = "\(value)"
                    }
                    .store(in: &cancellables)
            }
        }
    }

    @IBAction func checkboxAction(_ sender: NSButton) {
        guard let context = context else { return }
        let tasks = context.visibleTasks
        let tableView = context.tasksTableView!

        let row = tableView.row(for: self)
        guard row != -1 else { return }

        let clearOthers = NSEvent.modifierFlags.contains(.shift)

        let selectedRows = tableView.selectedRowIndexes.contains(row)
            ? tableView.selectedRowIndexes
            : IndexSet(integer: row)

        let value = (sender.state == .on)

        let selectedTasks = selectedRows.map { tasks.value[$0] }
        let clearedTasks = clearOthers
            ? (IndexSet(integersIn: 0 ..< tableView.numberOfRows)
                .subtracting(selectedRows)
                .map { tasks.value[$0] })
            : []

//        selectedTasks.forEach { $0.checked.apply(.beginTransaction) }
//        clearedTasks.forEach { $0.checked.apply(.beginTransaction) }
        selectedTasks.forEach { $0.checked.value = clearOthers ? true : value }
        clearedTasks.forEach { $0.checked.value = false }
//        selectedTasks.forEach { $0.checked.apply(.endTransaction) }
//        clearedTasks.forEach { $0.checked.apply(.endTransaction) }
        
        // FIXME: EK - Signalling about changes in a Task model. To update chart config in response
        // This is uuuugly as hell
        context.model.value.tasks.value = context.model.value.tasks.value
    }
}
