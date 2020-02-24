// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import Combine
import BenchmarkModel

extension NSUserInterfaceItemIdentifier {
    static let taskColumn = NSUserInterfaceItemIdentifier(rawValue: "TaskColumn")
}

class CombineTableViewController<Item: Hashable, CellView: NSTableCellView>: NSObject, NSTableViewDelegate, NSTableViewDataSource {
    
    let tableView: NSTableView
    let contents: CurrentValueSubject<[Item], Never>
    let selectedItems: AnyPublisher<[Item], Never>

    private let configure: (CellView, Item) -> Void
    private var selectedRows: IndexSet
    private let selectedItemsSubject = CurrentValueSubject<[Item], Never>([])
    private var cancellables: Set<AnyCancellable> = []

    init(tableView: NSTableView, contents: CurrentValueSubject<[Item], Never>, configure: @escaping (CellView, Item) -> Void) {
        self.tableView = tableView
        self.contents = contents
        self.configure = configure
        self.selectedRows = tableView.selectedRowIndexes
        self.selectedItemsSubject.value = selectedRows.map { contents.value[$0] }
        self.selectedItems = selectedItemsSubject.eraseToAnyPublisher()
        super.init()
        
        contents
            .sink { [unowned self] _ in
                self.apply()
            }
            .store(in: &cancellables)
    }

    func apply() {
        // TODO: EK - diffing for removing/inserting rows
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return contents.value.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier, id == .taskColumn else { return nil }
        
        let item = contents.value[row]
        let cell = tableView.makeView(withIdentifier: .taskColumn, owner: nil) as! CellView
        configure(cell, item)
        return cell
    }

    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
        proposedSelectionIndexes
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRows = tableView.selectedRowIndexes
        self.selectedRows = selectedRows
        self.selectedItemsSubject.value = selectedRows.map { contents.value[$0] }
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        false
    }

    func tableView(_ tableView: NSTableView, shouldSelect tableColumn: NSTableColumn?) -> Bool {
        false
    }
}
