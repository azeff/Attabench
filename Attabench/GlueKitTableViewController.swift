// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import Combine
import BenchmarkModel

extension NSUserInterfaceItemIdentifier {
    static let taskColumn = NSUserInterfaceItemIdentifier(rawValue: "TaskColumn")
}

class GlueKitTableViewController<Item: Hashable, CellView: NSTableCellView>: NSObject, NSTableViewDelegate, NSTableViewDataSource {
    
    let tableView: NSTableView
    let configure: (CellView, Item) -> Void
    let contents: CurrentValueSubject<[Item], Never>
    let selectedItems: AnyPublisher<[Item], Never>

    private var _selectedRows: IndexSet
    private let _selectedItems = CurrentValueSubject<[Item], Never>([])
    private var cancellables: Set<AnyCancellable> = []

    init(tableView: NSTableView, contents: CurrentValueSubject<[Item], Never>, configure: @escaping (CellView, Item) -> Void) {
        self.tableView = tableView
        self.contents = contents
        self.configure = configure
        self._selectedRows = tableView.selectedRowIndexes
        self._selectedItems.value = _selectedRows.map { contents.value[$0] }
        self.selectedItems = _selectedItems.eraseToAnyPublisher()
        super.init()
        
        contents
            .sink { [unowned self] _ in
                self.apply()
            }
            .store(in: &cancellables)
    }

    func apply() {
        tableView.reloadData()
//        let batch = change.separated()
//        tableView.beginUpdates()
//        tableView.removeRows(at: batch.deleted, withAnimation: [.effectFade, .slideUp])
//        tableView.insertRows(at: batch.inserted, withAnimation: [.effectFade, .slideDown])
//        for (from, to) in batch.moved {
//            tableView.moveRow(at: from, to: to)
//        }
//        tableView.endUpdates()
        //print("Removed: \(batch.deleted), inserted: \(batch.inserted), moved: \(batch.moved)")
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return contents.value.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier, id == .taskColumn else { return nil }
        let item = contents.value[row]
        let cell = tableView.makeView(withIdentifier: .taskColumn, owner: nil) as! CellView
        self.configure(cell, item)
        return cell
    }

    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
        return proposedSelectionIndexes
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRows = tableView.selectedRowIndexes
        self._selectedRows = selectedRows
        self._selectedItems.value = selectedRows.map { contents.value[$0] }
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelect tableColumn: NSTableColumn?) -> Bool {
        return false
    }
}
