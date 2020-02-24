// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import Combine
import BenchmarkModel
import BenchmarkRunner
import BenchmarkCharts
import BenchmarkIPC

enum UTI {
    static let png = "public.png"
    static let pdf = "com.adobe.pdf"
    static let attabench = "org.attaswift.attabench-benchmark"
    static let attaresult = "org.attaswift.attabench-results"
}

let attaresultExtension = NSWorkspace.shared.preferredFilenameExtension(forType: UTI.attaresult)!

enum ConsoleAttributes {
    private static let indentedParagraphStyle: NSParagraphStyle = {
        let style = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        style.headIndent = 12
        style.firstLineHeadIndent = 12
        return style
    }()
    static let standardOutput: [NSAttributedString.Key: Any] = [
        .font: NSFont(name: "Menlo-Regular", size: 12) ?? NSFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor(white: 0.3, alpha: 1),
        .paragraphStyle: indentedParagraphStyle
    ]
    static let standardError: [NSAttributedString.Key: Any] = [
        .font: NSFont(name: "Menlo-Bold", size: 12) ?? NSFont.systemFont(ofSize: 12, weight: .bold),
        .foregroundColor: NSColor(white: 0.3, alpha: 1),
        .paragraphStyle: indentedParagraphStyle
    ]
    static let statusMessage: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.black,
        .paragraphStyle: NSParagraphStyle.default
    ]
    static let errorMessage: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .bold),
        .foregroundColor: NSColor.black,
        .paragraphStyle: NSParagraphStyle.default
    ]
}

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

class AttabenchDocument: NSDocument, BenchmarkDelegate {

    enum State {
        case noBenchmark
        case idle
        case loading(BenchmarkProcess)
        case waiting // We should be running, but parameters aren't ready yet
        case running(BenchmarkProcess)
        case stopping(BenchmarkProcess, then: Followup)
        case failedBenchmark

        enum Followup {
            case idle
            case reload
            case restart
        }

        var process: BenchmarkProcess? {
            switch self {
            case .loading(let process): return process
            case .running(let process): return process
            case .stopping(let process, _): return process
            default: return nil
            }
        }
    }

    var state: State = .noBenchmark {
        didSet { stateDidChange(from: oldValue, to: state) }
    }
    var activity: NSObjectProtocol? // Preventing system sleep

    let model = CurrentValueSubject<Attaresult, Never>(Attaresult())
//    var m: Attaresult {
//        get { return model.value }
//        set { model.value = newValue }
//    }
    
    let taskFilterString = CurrentValueSubject<String?, Never>(nil)
    let taskFilter = CurrentValueSubject<TaskFilter, Never>(TaskFilter(nil))
    
    let visibleTasks = CurrentValueSubject<[Task], Never>([])
    let checkedTasks = CurrentValueSubject<[Task], Never>([])
    let tasksToRun = CurrentValueSubject<[Task], Never>([])

    let batchCheckboxState = CurrentValueSubject<NSControl.StateValue, Never>(.on)

    let theme = CurrentValueSubject<BenchmarkTheme, Never>(BenchmarkTheme.Predefined.screen)

    var _log: NSMutableAttributedString? = nil
    var _status: String = "Ready"

    lazy var refreshChart = RateLimiter(maxDelay: 5, async: true) { [unowned self] in self._refreshChart() }
    var tasksTableViewController: GlueKitTableViewController<Task, TaskCellView>?

    var pendingResults: [(task: String, size: Int, time: Time)] = []
    lazy var processPendingResults = RateLimiter(maxDelay: 0.2) { [unowned self] in
        for (task, size, time) in self.pendingResults {
            self.model.value.addMeasurement(time, forTask: task, size: size)
        }
        self.pendingResults = []
        self.updateChangeCount(.changeDone)
        self.refreshChart.later()
    }

    @IBOutlet weak var runButton: NSButton?
    @IBOutlet weak var minimumSizeButton: NSPopUpButton?
    @IBOutlet weak var maximumSizeButton: NSPopUpButton?
    @IBOutlet weak var rootSplitView: NSSplitView?

    @IBOutlet weak var leftPane: NSVisualEffectView?
    @IBOutlet weak var leftVerticalSplitView: NSSplitView?
    @IBOutlet weak var tasksTableView: NSTableView?
    @IBOutlet weak var leftBar: ColoredView?
    @IBOutlet weak var batchCheckbox: NSButtonCell!
    @IBOutlet weak var taskFilterTextField: NSSearchField!
    @IBOutlet weak var showRunOptionsButton: NSButton?
    @IBOutlet weak var runOptionsPane: ColoredView?
    @IBOutlet weak var iterationsField: NSTextField?
    @IBOutlet weak var iterationsStepper: NSStepper?
    @IBOutlet weak var minimumDurationField: NSTextField?
    @IBOutlet weak var maximumDurationField: NSTextField?

    @IBOutlet weak var middleSplitView: NSSplitView?
    @IBOutlet weak var chartView: ChartView?
    @IBOutlet weak var middleBar: ColoredView?
    @IBOutlet weak var showLeftPaneButton: NSButton?
    @IBOutlet weak var showConsoleButton: NSButton?
    @IBOutlet weak var statusLabel: StatusLabel?
    @IBOutlet weak var showRightPaneButton: NSButton?
    @IBOutlet weak var consolePane: NSView?
    @IBOutlet weak var consoleTextView: NSTextView?

    @IBOutlet weak var rightPane: ColoredView?
    
    @IBOutlet weak var themePopUpButton: NSPopUpButton?
    @IBOutlet weak var amortizedCheckbox: NSButton?
    @IBOutlet weak var logarithmicSizeCheckbox: NSButton?
    @IBOutlet weak var logarithmicTimeCheckbox: NSButton?

    @IBOutlet weak var centerBandPopUpButton: NSPopUpButton?
    @IBOutlet weak var errorBandPopUpButton: NSPopUpButton?
    
    @IBOutlet weak var highlightSelectedSizeRangeCheckbox: NSButton?
    @IBOutlet weak var displayIncludeAllMeasuredSizesCheckbox: NSButton?
    @IBOutlet weak var displayIncludeSizeScaleRangeCheckbox: NSButton?
    @IBOutlet weak var displaySizeScaleRangeMinPopUpButton: NSPopUpButton?
    @IBOutlet weak var displaySizeScaleRangeMaxPopUpButton: NSPopUpButton?

    @IBOutlet weak var displayIncludeAllMeasuredTimesCheckbox: NSButton?
    @IBOutlet weak var displayIncludeTimeRangeCheckbox: NSButton?
    @IBOutlet weak var displayTimeRangeMinPopUpButton: NSPopUpButton?
    @IBOutlet weak var displayTimeRangeMaxPopUpButton: NSPopUpButton?

    @IBOutlet weak var progressRefreshIntervalField: NSTextField?
    @IBOutlet weak var chartRefreshIntervalField: NSTextField?

    // ---------
    
    private var cancellables = Set<AnyCancellable>()
    
    private func privateInit() {
        taskFilterString
            .map(TaskFilter.init)
            .subscribe(taskFilter)
            .store(in: &cancellables)
        
        model
            .map(\.tasks)
            .switchToLatest()
            .combineLatest(taskFilter) { tasks, filter in
                tasks.filter(filter.test)
            }
            .subscribe(visibleTasks)
            .store(in: &cancellables)
        
        visibleTasks
            .map { tasks in
                tasks.filter { $0.checked.value }
            }
            .subscribe(checkedTasks)
            .store(in: &cancellables)

        visibleTasks
            .map { tasks in
                tasks.filter { $0.checked.value && $0.isRunnable.value }
            }
            .subscribe(tasksToRun)
            .store(in: &cancellables)
        
        let visibleCount = visibleTasks.map(\.count)
        let checkedCount = checkedTasks.map(\.count)
        visibleCount
            .combineLatest(checkedCount) { c1, c2 in
                if c1 == c2 { return .on }
                if c2 == 0 { return .off }
                return .mixed
            }
            .subscribe(batchCheckboxState)
            .store(in: &cancellables)
    }
    
    // -----------
    
    override init() {
        super.init()
        
        privateInit()

        // TODO: EK - why data flows this way? Shouldn't it be the other way around?
        theme.map(\.name).subscribe(model.value.themeName).store(in: &cancellables)
//        self.glue.connector.connect(self.theme.values) { [unowned self] theme in
//            self.model.value.themeName.value = theme.name
//        }
        
//        self.glue.connector.connect([tasksToRun.tick, model.map{$0.runOptionsTick}].gather()) { [unowned self] in
//            self.updateChangeCount(.changeDone)
//            self.runOptionsDidChange()
//        }
        Publishers
            .Merge(
                tasksToRun.map({ _ in Void() }),
                model.map(\.runOptionsTick).switchToLatest()
            )
            .sink { [unowned self] _ in
                self.updateChangeCount(.changeDone)
                self.runOptionsDidChange()
            }
            .store(in: &cancellables)
        
//        self.glue.connector.connect([checkedTasks.tick,
//                                     model.map{$0.runOptionsTick},
//                                     model.map{$0.chartOptionsTick}].gather()) { [unowned self] in
//            self.updateChangeCount(.changeDone)
//            self.refreshChart.now()
//        }
        Publishers
            .Merge3(
                checkedTasks.map({ _ in Void() }),
                model.map(\.runOptionsTick).switchToLatest(),
                model.map(\.chartOptionsTick).switchToLatest()
            )
            .sink { [unowned self] in
                self.updateChangeCount(.changeDone)
                self.refreshChart.now()
            }
            .store(in: &cancellables)

//        self.glue.connector.connect(batchCheckboxState.futureValues) { [unowned self] state in
//            self.batchCheckbox?.state = state
//        }
        batchCheckboxState
            .dropFirst(1)
            .sink { [unowned self] state in
                self.batchCheckbox?.state = state
            }
            .store(in: &cancellables)
        
//        self.glue.connector.connect(taskFilterString.futureValues) { [unowned self] filter in
//            guard let field = self.taskFilterTextField else { return }
//            if field.stringValue != filter {
//                self.taskFilterTextField.stringValue = filter ?? ""
//            }
//        }
        taskFilterString
            .dropFirst(1)
            .sink { [unowned self] filter in
                guard let field = self.taskFilterTextField, field.stringValue != filter else { return }
                self.taskFilterTextField.stringValue = filter ?? ""
            }
            .store(in: &cancellables)
        
//        self.glue.connector.connect(model.map{$0.progressRefreshInterval}.values) { [unowned self] interval in
//            self.statusLabel?.refreshRate = interval.seconds
//            self.processPendingResults.maxDelay = interval.seconds
//        }
        model
            .map(\.progressRefreshInterval)
            .switchToLatest()
            .sink { [unowned self] interval in
                self.statusLabel?.refreshRate = interval.seconds
                self.processPendingResults.maxDelay = interval.seconds
            }
            .store(in: &cancellables)
        
//        self.glue.connector.connect(model.map{$0.chartRefreshInterval}.values) { [unowned self] interval in
//            self.refreshChart.maxDelay = interval.seconds
//        }
        model
            .map(\.chartRefreshInterval)
            .switchToLatest()
            .sink { [unowned self] interval in
                self.refreshChart.maxDelay = interval.seconds
            }
            .store(in: &cancellables)
    }

    deinit {
        self.state = .idle
    }

    override var windowNibName: NSNib.Name? {
        // Returns the nib file name of the document
        // If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this property and override -makeWindowControllers instead.
        return "AttabenchDocument"
    }

    @objc
    private func didChangeIterationsStepper() {
        guard let iterations = self.iterationsStepper?.objectValue as? Int else { return }
        model.value.iterations.value = iterations
    }
    
    @objc
    private func didChangeMinDuration() {
        guard
            let lowerBoundString = self.minimumDurationField?.stringValue,
            let lowerBound = Time(lowerBoundString)
            else { return }
        model.value.durationRange.lowerBound = lowerBound
    }
    
    @objc
    private func didChangeMaxDuration() {
        guard
            let upperBoundString = self.maximumDurationField?.stringValue,
            let upperBound = Time(upperBoundString)
            else { return }
        model.value.durationRange.upperBound = upperBound
    }
    
    @objc
    private func didChangeAmortizedCheckbox() {
        guard let state = self.amortizedCheckbox?.state else { return }
        model.value.amortizedTime.value = state == .on
    }
    
    @objc
    private func didChangeLogarithmicSizeCheckbox() {
        guard let state = self.logarithmicSizeCheckbox?.state else { return }
        model.value.logarithmicSizeScale.value = state == .on
    }
    
    @objc
    private func didChangeLogarithmicTimeCheckbox() {
        guard let state = self.logarithmicTimeCheckbox?.state else { return }
        model.value.logarithmicTimeScale.value = state == .on
    }
    
    @objc
    private func didChangeProgressRefreshInterval() {
        guard
            let intervalString = progressRefreshIntervalField?.stringValue,
            let intervalTime = Time(intervalString)
            else { return }
        
        model.value.progressRefreshInterval.value = intervalTime
    }
    
    @objc
    private func didChangeChartRefreshInterval() {
        guard
            let intervalString = chartRefreshIntervalField?.stringValue,
            let intervalTime = Time(intervalString)
            else { return }
        
        model.value.chartRefreshInterval.value = intervalTime
    }
    
    @objc
    private func didChangeHighlightSelectedSizeRangeCheckbox() {
        guard let state = highlightSelectedSizeRangeCheckbox?.state else { return }
        model.value.highlightSelectedSizeRange.value = state == .on
    }
    
    @objc
    private func didChangeDisplayIncludeAllMeasuredSizesCheckbox() {
        guard let state = displayIncludeAllMeasuredSizesCheckbox?.state else { return }
        model.value.displayIncludeAllMeasuredSizes.value = state == .on
    }
    
    @objc
    private func didChangeDisplayIncludeSizeScaleRangeCheckbox() {
        guard let state = displayIncludeSizeScaleRangeCheckbox?.state else { return }
        model.value.displayIncludeSizeScaleRange.value = state == .on
    }
    
    @objc
    private func didChangeDisplayIncludeAllMeasuredTimesCheckbox() {
        guard let state = displayIncludeAllMeasuredTimesCheckbox?.state else { return }
        model.value.displayIncludeAllMeasuredTimes.value = state == .on
    }
    
    @objc
    private func didChangeDisplayIncludeTimeRangeCheckbox() {
        guard let state = displayIncludeTimeRangeCheckbox?.state else { return }
        model.value.displayIncludeTimeRange.value = state == .on
    }
    
    override func windowControllerDidLoadNib(_ windowController: NSWindowController) {
        super.windowControllerDidLoadNib(windowController)
        consoleTextView!.textStorage!.setAttributedString(_log ?? NSAttributedString())
        let tasksTVC = GlueKitTableViewController<Task, TaskCellView>(tableView: tasksTableView!, contents: visibleTasks) { [unowned self] cell, item in
            cell.task = item
            cell.context = self
        }
        self.tasksTableViewController = tasksTVC
        self.tasksTableView!.delegate = tasksTVC
        self.tasksTableView!.dataSource = tasksTVC
        self.statusLabel!.immediateStatus = _status
        self.chartView!.documentBasename = self.displayName
        self.chartView!.theme = self.theme
        self.batchCheckbox.state = self.batchCheckboxState.value

        let iterations = model.map(\.iterations).switchToLatest()
//        self.iterationsField!.glue.value <-- model.map{$0.iterations}
        iterations
            .sink { [unowned self] iterations in
                self.iterationsField?.stringValue = String(iterations)
            }
            .store(in: &cancellables)
//        self.iterationsStepper!.glue.intValue <-- model.map{$0.iterations}
        iterations
            .sink { [unowned self] iterations in
                self.iterationsStepper?.intValue = Int32(iterations)
            }
            .store(in: &cancellables)
        iterationsStepper?.target = self
        iterationsStepper?.action = #selector(didChangeIterationsStepper)

        let durationRange = model.map(\.durationRange)
//        self.minimumDurationField!.glue.value <-- model.map{$0.durationRange.lowerBound}
        durationRange
            .sink { [unowned self] range in
                self.minimumDurationField?.stringValue = String(range.lowerBound)
            }
            .store(in: &cancellables)
        minimumDurationField?.target = self
        minimumDurationField?.action = #selector(didChangeMinDuration)
        
//        self.maximumDurationField!.glue.value <-- model.map{$0.durationRange.upperBound}
        durationRange
            .sink { [unowned self] range in
                self.maximumDurationField?.stringValue = String(range.upperBound)
            }
            .store(in: &cancellables)
        minimumDurationField?.target = self
        minimumDurationField?.action = #selector(didChangeMaxDuration)

//        self.amortizedCheckbox!.glue.state <-- model.map{$0.amortizedTime}
        model
            .map(\.amortizedTime)
            .switchToLatest()
            .sink { [unowned self] amortizedTime in
                self.amortizedCheckbox?.state = amortizedTime ? .on : .off
            }
            .store(in: &cancellables)
        amortizedCheckbox?.target = self
        amortizedCheckbox?.action = #selector(didChangeAmortizedCheckbox)
        
//        self.logarithmicSizeCheckbox!.glue.state <-- model.map{$0.logarithmicSizeScale}
        model
            .map(\.logarithmicSizeScale)
            .switchToLatest()
            .sink { [unowned self] scale in
                self.logarithmicSizeCheckbox?.state = scale ? .on : .off
            }
            .store(in: &cancellables)
        logarithmicSizeCheckbox?.target = self
        logarithmicSizeCheckbox?.action = #selector(didChangeLogarithmicSizeCheckbox)

//        self.logarithmicTimeCheckbox!.glue.state <-- model.map{$0.logarithmicTimeScale}
        model
            .map(\.logarithmicTimeScale)
            .switchToLatest()
            .sink { [unowned self] scale in
                self.logarithmicTimeCheckbox?.state = scale ? .on : .off
            }
            .store(in: &cancellables)
        logarithmicTimeCheckbox?.target = self
        logarithmicTimeCheckbox?.action = #selector(didChangeLogarithmicTimeCheckbox)

//        self.progressRefreshIntervalField!.glue.value <-- model.map{$0.progressRefreshInterval}
        model
            .map(\.progressRefreshInterval)
            .switchToLatest()
            .sink { [unowned self] interval in
                self.progressRefreshIntervalField?.stringValue = String(interval)
            }
            .store(in: &cancellables)
        progressRefreshIntervalField?.target = self
        progressRefreshIntervalField?.action = #selector(didChangeProgressRefreshInterval)
        
//        self.chartRefreshIntervalField!.glue.value <-- model.map{$0.chartRefreshInterval}
        model
            .map(\.chartRefreshInterval)
            .switchToLatest()
            .sink { [unowned self] interval in
                self.chartRefreshIntervalField?.stringValue = String(interval)
            }
            .store(in: &cancellables)
        chartRefreshIntervalField?.target = self
        chartRefreshIntervalField?.action = #selector(didChangeChartRefreshInterval)

//        self.centerBandPopUpButton!.glue <-- NSPopUpButton.Choices<CurveBandValues>(
//            model: model.map{$0.centerBand}
//                .map({ CurveBandValues($0) },
//                     inverse: { $0.band }),
//            values: [
//                "None": .none,
//                "Minimum": .minimum,
//                "Average": .average,
//                "Maximum": .maximum,
//                "Sample Size": .count,
//            ])
        let bandChoices = [
            ("None", CurveBandValues.none),
            ("Minimum", CurveBandValues.minimum),
            ("Average", CurveBandValues.average),
            ("Maximum", CurveBandValues.maximum),
            ("Sample Size", CurveBandValues.count),
        ]
        let bandMenu = NSMenu()
        for (title, value) in bandChoices {
            let menuItem = NSMenuItem(title: title, action: #selector(didSelectBand), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = value
            bandMenu.addItem(menuItem)
        }
        centerBandPopUpButton?.menu = bandMenu
        func bindCenterBand() {
            model
                .map(\.centerBand)
                .switchToLatest()
                .sink { [unowned self] band in
                    let value = CurveBandValues(band)
                    guard
                        let menu = self.centerBandPopUpButton?.menu,
                        let item = menu.items.first(where: { ($0.representedObject as? CurveBandValues) == value })
                        else { return }
                    
                    if self.centerBandPopUpButton?.selectedItem != item {
                        self.centerBandPopUpButton?.select(item)
                    }
                }
                .store(in: &cancellables)
        }
        bindCenterBand()

//        self.errorBandPopUpButton!.glue <-- NSPopUpButton.Choices<ErrorBandValues>(
//            model: model.map{$0.topBand}.combined(model.map{$0.bottomBand})
//                .map({ ErrorBandValues(top: $0.0, bottom: $0.1) },
//                     inverse: { ($0.top, $0.bottom) }),
//            values: [
//                "None": .none,
//                "Maximum": .maximum,
//                "μ + σ": .sigma1,
//                "μ + 2σ": .sigma2,
//                "μ + 3σ": .sigma3,
//            ])
        let availableErrorBands = [
            ("None", ErrorBandValues.none),
            ("Maximum", ErrorBandValues.maximum),
            ("μ + σ", ErrorBandValues.sigma1),
            ("μ + 2σ", ErrorBandValues.sigma2),
            ("μ + 3σ", ErrorBandValues.sigma3),
        ]
        let errorBandMenu = NSMenu()
        for (title, value) in availableErrorBands {
            let errorItem = NSMenuItem(title: title, action: #selector(didSelectErrorBand), keyEquivalent: "")
            errorItem.target = self
            errorItem.representedObject = value
            errorBandMenu.addItem(errorItem)
        }
        errorBandPopUpButton?.menu = errorBandMenu
        func bindErrorBand() {
            let topBand = model.map(\.topBand).switchToLatest()
            let bottomBand = model.map(\.bottomBand).switchToLatest()
            topBand
                .combineLatest(bottomBand) { top, bottom in
                    ErrorBandValues(top: top, bottom: bottom)
                }
                .sink { [unowned self] value in
                    guard
                        let menu = self.errorBandPopUpButton?.menu,
                        let item = menu.items.first(where: { ($0.representedObject as? ErrorBandValues) == value })
                        else { return }
                    
                    if self.errorBandPopUpButton?.selectedItem != item {
                        self.errorBandPopUpButton?.select(item)
                    }
                }
                .store(in: &cancellables)
        }
        bindErrorBand()
        
//        self.themePopUpButton!.glue <-- NSPopUpButton.Choices<BenchmarkTheme>(
//            model: self.theme,
//            values: BenchmarkTheme.Predefined.themes.map { (label: $0.name, value: $0) })
        let availableThemes = BenchmarkTheme.Predefined.themes.map { (label: $0.name, value: $0) }
        let themeMenu = NSMenu()
        for (title, value) in availableThemes {
            let themeItem = NSMenuItem(title: title, action: #selector(didSelectTheme), keyEquivalent: "")
            themeItem.target = self
            themeItem.representedObject = value
            themeMenu.addItem(themeItem)
        }
        themePopUpButton?.menu = themeMenu
        func bindTheme() {
            self.theme
                .sink { [unowned self] value in
                    guard
                        let menu = self.themePopUpButton?.menu,
                        let item = menu.items.first(where: { ($0.representedObject as? BenchmarkTheme) == value })
                        else { return }
                    
                    if self.themePopUpButton?.selectedItem != item {
                        self.themePopUpButton?.select(item)
                    }
                }
                .store(in: &cancellables)
        }
        bindTheme()
        
        let sizeChoices: [(label: String, value: Int)]
            = (0 ... Attaresult.largestPossibleSizeScale).map { ((1 << $0).sizeLabel, $0) }
        let lowerBoundSizeChoices = sizeChoices.map { (label: "\($0.0) ≤", value: $0.1) }
        let upperBoundSizeChoices = sizeChoices.map { (label: "≤ \($0.0)", value: $0.1) }
        
//        self.minimumSizeButton!.glue <-- NSPopUpButton.Choices<Int>(
//            model: model.map{$0.sizeScaleRange.lowerBound},
//            values: lowerBoundSizeChoices)
        let minimumSizeMenu = NSMenu()
        for (title, value) in lowerBoundSizeChoices {
            let minimumSizeItem = NSMenuItem(title: title, action: #selector(didSelectMinimumSize), keyEquivalent: "")
            minimumSizeItem.target = self
            minimumSizeItem.representedObject = value
            minimumSizeMenu.addItem(minimumSizeItem)
        }
        minimumSizeButton?.menu = minimumSizeMenu
        func bindMinimumSize() {
            model.map(\.sizeScaleRange.lowerBoundPublisher)
                .switchToLatest()
                .sink { [unowned self] value in
                    guard
                        let menu = self.minimumSizeButton?.menu,
                        let item = menu.items.first(where: { ($0.representedObject as? Int) == value })
                        else { return }
                    
                    if self.minimumSizeButton?.selectedItem != item {
                        self.minimumSizeButton?.select(item)
                    }
                }
                .store(in: &cancellables)
        }
        bindMinimumSize()
        
//        self.maximumSizeButton!.glue <-- NSPopUpButton.Choices<Int>(
//            model: model.map{$0.sizeScaleRange.upperBound},
//            values: upperBoundSizeChoices)
        let maximumSizeMenu = NSMenu()
        for (title, value) in upperBoundSizeChoices {
            let maximumSizeItem = NSMenuItem(title: title, action: #selector(didSelectMaximumSize), keyEquivalent: "")
            maximumSizeItem.target = self
            maximumSizeItem.representedObject = value
            maximumSizeMenu.addItem(maximumSizeItem)
        }
        maximumSizeButton?.menu = maximumSizeMenu
        func bindMaximumSize() {
            model.map(\.sizeScaleRange.upperBoundPublisher)
                .switchToLatest()
                .sink { [unowned self] value in
                    guard
                        let menu = self.maximumSizeButton?.menu,
                        let item = menu.items.first(where: { ($0.representedObject as? Int) == value })
                        else { return }
                    
                    if self.maximumSizeButton?.selectedItem != item {
                        self.maximumSizeButton?.select(item)
                    }
                }
                .store(in: &cancellables)
        }
        bindMaximumSize()
        
//        self.highlightSelectedSizeRangeCheckbox!.glue.state <-- model.map{$0.highlightSelectedSizeRange}
        model.map(\.highlightSelectedSizeRange).switchToLatest()
            .sink { [unowned self] selected in
                self.highlightSelectedSizeRangeCheckbox?.state = selected ? .on : .off
            }
            .store(in: &cancellables)
        highlightSelectedSizeRangeCheckbox?.target = self
        highlightSelectedSizeRangeCheckbox?.action = #selector(didChangeHighlightSelectedSizeRangeCheckbox)
        
//        self.displayIncludeAllMeasuredSizesCheckbox!.glue.state <-- model.map{$0.displayIncludeAllMeasuredSizes}
        model.map(\.displayIncludeAllMeasuredSizes).switchToLatest()
            .sink { [unowned self] selected in
                self.displayIncludeAllMeasuredSizesCheckbox?.state = selected ? .on : .off
            }
            .store(in: &cancellables)
        displayIncludeAllMeasuredSizesCheckbox?.target = self
        displayIncludeAllMeasuredSizesCheckbox?.action = #selector(didChangeDisplayIncludeAllMeasuredSizesCheckbox)

//        self.displayIncludeSizeScaleRangeCheckbox!.glue.state <-- model.map{$0.displayIncludeSizeScaleRange}
        model.map(\.displayIncludeSizeScaleRange).switchToLatest()
            .sink { [unowned self] selected in
                self.displayIncludeSizeScaleRangeCheckbox?.state = selected ? .on : .off
            }
            .store(in: &cancellables)
        displayIncludeSizeScaleRangeCheckbox?.target = self
        displayIncludeSizeScaleRangeCheckbox?.action = #selector(didChangeDisplayIncludeSizeScaleRangeCheckbox)
        
//        self.displaySizeScaleRangeMinPopUpButton!.glue <-- NSPopUpButton.Choices<Int>(
//            model: model.map{$0.displaySizeScaleRange.lowerBound},
//            values: lowerBoundSizeChoices)
        let scaleRangeLowerBoundMenu = NSMenu()
        for (title, value) in lowerBoundSizeChoices {
            let scaleRangeItem = NSMenuItem(title: title, action: #selector(didSelectScaleRangeLowerBound), keyEquivalent: "")
            scaleRangeItem.target = self
            scaleRangeItem.representedObject = value
            scaleRangeLowerBoundMenu.addItem(scaleRangeItem)
        }
        displaySizeScaleRangeMinPopUpButton?.menu = scaleRangeLowerBoundMenu
        func bindDisplaySizeScaleRangeMin() {
            model.map(\.displaySizeScaleRange.lowerBoundPublisher)
                .switchToLatest()
                .sink { [unowned self] value in
                    guard
                        let menu = self.displaySizeScaleRangeMinPopUpButton?.menu,
                        let item = menu.items.first(where: { ($0.representedObject as? Int) == value })
                        else { return }
                    
                    if self.displaySizeScaleRangeMinPopUpButton?.selectedItem != item {
                        self.displaySizeScaleRangeMinPopUpButton?.select(item)
                    }
                }
                .store(in: &cancellables)
        }
        bindDisplaySizeScaleRangeMin()
        
//        self.displaySizeScaleRangeMinPopUpButton!.glue.isEnabled <-- model.map{$0.displayIncludeSizeScaleRange}
        model.map(\.displayIncludeSizeScaleRange).switchToLatest()
            .sink { [unowned self] enabled in
                self.displaySizeScaleRangeMinPopUpButton?.isEnabled = enabled
            }
            .store(in: &cancellables)

//        self.displaySizeScaleRangeMaxPopUpButton!.glue <-- NSPopUpButton.Choices<Int>(
//            model: model.map{$0.displaySizeScaleRange.upperBound},
//            values: upperBoundSizeChoices)
        let scaleRangeUpperBoundMenu = NSMenu()
        for (title, value) in upperBoundSizeChoices {
            let scaleRangeItem = NSMenuItem(title: title, action: #selector(didSelectScaleRangeUpperBound), keyEquivalent: "")
            scaleRangeItem.target = self
            scaleRangeItem.representedObject = value
            scaleRangeUpperBoundMenu.addItem(scaleRangeItem)
        }
        displaySizeScaleRangeMaxPopUpButton?.menu = scaleRangeUpperBoundMenu
        func bindDisplaySizeScaleRangeMax() {
            model.map(\.displaySizeScaleRange.upperBoundPublisher)
                .switchToLatest()
                .sink { [unowned self] value in
                    guard
                        let menu = self.displaySizeScaleRangeMaxPopUpButton?.menu,
                        let item = menu.items.first(where: { ($0.representedObject as? Int) == value })
                        else { return }
                    
                    if self.displaySizeScaleRangeMaxPopUpButton?.selectedItem != item {
                        self.displaySizeScaleRangeMaxPopUpButton?.select(item)
                    }
                }
                .store(in: &cancellables)
        }
        bindDisplaySizeScaleRangeMax()
        
//        self.displaySizeScaleRangeMaxPopUpButton!.glue.isEnabled <-- model.map{$0.displayIncludeSizeScaleRange}
        model.map(\.displayIncludeSizeScaleRange).switchToLatest()
            .sink { [unowned self] enabled in
                self.displaySizeScaleRangeMaxPopUpButton?.isEnabled = enabled
            }
            .store(in: &cancellables)

        
        var timeChoices: [(label: String, value: Time)] = []
        var time = Time(picoseconds: 1)
        for _ in 0 ..< 20 {
            timeChoices.append(("\(time)", time))
            time = 10 * time
        }
//        self.displayIncludeAllMeasuredTimesCheckbox!.glue.state <-- model.map{$0.displayIncludeAllMeasuredTimes}
        model.map(\.displayIncludeAllMeasuredTimes).switchToLatest()
            .sink { [unowned self] checked in
                self.displayIncludeAllMeasuredTimesCheckbox?.state = checked ? .on : .off
            }
            .store(in: &cancellables)
        displayIncludeAllMeasuredTimesCheckbox?.target = self
        displayIncludeAllMeasuredTimesCheckbox?.action = #selector(didChangeDisplayIncludeAllMeasuredTimesCheckbox)

//        self.displayIncludeTimeRangeCheckbox!.glue.state <-- model.map{$0.displayIncludeTimeRange}
        model.map(\.displayIncludeTimeRange).switchToLatest()
            .sink { [unowned self] checked in
                self.displayIncludeTimeRangeCheckbox?.state = checked ? .on : .off
            }
            .store(in: &cancellables)
        displayIncludeTimeRangeCheckbox?.target = self
        displayIncludeTimeRangeCheckbox?.action = #selector(didChangeDisplayIncludeTimeRangeCheckbox)

//        self.displayTimeRangeMinPopUpButton!.glue <-- NSPopUpButton.Choices<Time>(
//            model: model.map{$0.displayTimeRange.lowerBound},
//            values: timeChoices)
        let displayTimeLowerBoundMenu = NSMenu()
        for (title, value) in timeChoices {
            let rangeItem = NSMenuItem(title: title, action: #selector(didSelectDisplayTimeLowerBound), keyEquivalent: "")
            rangeItem.target = self
            rangeItem.representedObject = value
            displayTimeLowerBoundMenu.addItem(rangeItem)
        }
        displayTimeRangeMinPopUpButton?.menu = displayTimeLowerBoundMenu
        func bindDisplayTimeRangeMin() {
            model.map(\.displayTimeRange.lowerBoundPublisher)
                .switchToLatest()
                .sink { [unowned self] value in
                    guard
                        let menu = self.displayTimeRangeMinPopUpButton?.menu,
                        let item = menu.items.first(where: { ($0.representedObject as? Time) == value })
                        else { return }
                    
                    if self.displayTimeRangeMinPopUpButton?.selectedItem != item {
                        self.displayTimeRangeMinPopUpButton?.select(item)
                    }
                }
                .store(in: &cancellables)
        }
        bindDisplayTimeRangeMin()
        
//        self.displayTimeRangeMinPopUpButton!.glue.isEnabled <-- model.map{$0.displayIncludeTimeRange}
        model.map(\.displayIncludeTimeRange).switchToLatest()
            .sink { [unowned self] enabled in
                self.displayTimeRangeMinPopUpButton?.isEnabled = enabled
            }
            .store(in: &cancellables)

//        self.displayTimeRangeMaxPopUpButton!.glue <-- NSPopUpButton.Choices<Time>(
//            model: model.map{$0.displayTimeRange.upperBound},
//            values: timeChoices)
        let displayTimeUpperBoundMenu = NSMenu()
        for (title, value) in timeChoices {
            let rangeItem = NSMenuItem(title: title, action: #selector(didSelectDisplayTimeUpperBound), keyEquivalent: "")
            rangeItem.target = self
            rangeItem.representedObject = value
            displayTimeUpperBoundMenu.addItem(rangeItem)
        }
        displayTimeRangeMaxPopUpButton?.menu = displayTimeUpperBoundMenu
        func bindDisplayTimeRangeMax() {
            model.map(\.displayTimeRange.upperBoundPublisher)
                .switchToLatest()
                .sink { [unowned self] value in
                    guard
                        let menu = self.displayTimeRangeMaxPopUpButton?.menu,
                        let item = menu.items.first(where: { ($0.representedObject as? Time) == value })
                        else { return }
                    
                    if self.displayTimeRangeMaxPopUpButton?.selectedItem != item {
                        self.displayTimeRangeMaxPopUpButton?.select(item)
                    }
                }
                .store(in: &cancellables)
        }
        bindDisplayTimeRangeMax()
        
//        self.displayTimeRangeMaxPopUpButton!.glue.isEnabled <-- model.map{$0.displayIncludeTimeRange}
        model.map(\.displayIncludeTimeRange).switchToLatest()
            .sink { [unowned self] enabled in
                self.displayTimeRangeMaxPopUpButton?.isEnabled = enabled
            }
            .store(in: &cancellables)

        refreshRunButton()
        refreshChart.now()
    }
    
    enum CurveBandValues: Equatable {
        case none
        case average
        case minimum
        case maximum
        case count
        case other(TimeSample.Band?)

        init(_ band: TimeSample.Band?) {
            switch band {
            case nil: self = .none
            case .average?: self = .average
            case .minimum?: self = .minimum
            case .maximum?: self = .maximum
            case .count?: self = .count
            default: self = .other(band)
            }
        }

        var band: TimeSample.Band? {
            switch self {
            case .none: return nil
            case .average: return .average
            case .minimum: return .minimum
            case .maximum: return .maximum
            case .count: return .count
            case .other(let band): return band
            }
        }

        static func ==(left: CurveBandValues, right: CurveBandValues) -> Bool {
            return left.band == right.band
        }
    }

    enum ErrorBandValues: Equatable {
        case none
        case maximum
        case sigma1
        case sigma2
        case sigma3
        case other(top: TimeSample.Band?, bottom: TimeSample.Band?)

        var top: TimeSample.Band? {
            switch self {
            case .none: return nil
            case .maximum: return .maximum
            case .sigma1: return .sigma(1)
            case .sigma2: return .sigma(2)
            case .sigma3: return .sigma(3)
            case .other(top: let top, bottom: _): return top
            }
        }

        var bottom: TimeSample.Band? {
            switch self {
            case .none: return nil
            case .maximum: return .minimum
            case .sigma1: return .minimum
            case .sigma2: return .minimum
            case .sigma3: return .minimum
            case .other(top: _, bottom: let bottom): return bottom
            }
        }

        init(top: TimeSample.Band?, bottom: TimeSample.Band?) {
            switch (top, bottom) {
            case (nil, nil): self = .none
            case (.maximum?, .minimum?): self = .maximum
            case (.sigma(1)?, .minimum?): self = .sigma1
            case (.sigma(2)?, .minimum?): self = .sigma2
            case (.sigma(3)?, .minimum?): self = .sigma3
            case let (t, b): self = .other(top: t, bottom: b)
            }
        }

        static func ==(left: ErrorBandValues, right: ErrorBandValues) -> Bool {
            return left.top == right.top && left.bottom == right.bottom
        }

    }

    func stateDidChange(from old: State, to new: State) {
        switch old {
        case .loading(let process):
            process.stop()
        case .running(let process):
            process.stop()
        default:
            break
        }

        let name = model.value.benchmarkDisplayName.value

        switch new {
        case .noBenchmark:
            self.setStatus(.immediate, "Attabench document cannot be found; can't take new measurements")
        case .idle:
            self.setStatus(.immediate, "Ready")
        case .loading(_):
            self.setStatus(.immediate, "Loading \(name)...")
        case .waiting:
            self.setStatus(.immediate, "No executable tasks selected, pausing")
        case .running(_):
            self.setStatus(.immediate, "Starting \(name)...")
        case .stopping(_, then: .restart):
            self.setStatus(.immediate, "Restarting \(name)...")
        case .stopping(_, then: _):
            self.setStatus(.immediate, "Stopping \(name)...")
        case .failedBenchmark:
            self.setStatus(.immediate, "Failed")
        }
        self.refreshRunButton()
    }

    func refreshRunButton() {
        switch state {
        case .noBenchmark:
            self.runButton?.isEnabled = false
            self.runButton?.image = #imageLiteral(resourceName: "RunTemplate")
        case .idle:
            self.runButton?.isEnabled = true
            self.runButton?.image = #imageLiteral(resourceName: "RunTemplate")
        case .loading(_):
            self.runButton?.isEnabled = true
            self.runButton?.image = #imageLiteral(resourceName: "StopTemplate")
        case .waiting:
            self.runButton?.isEnabled = true
            self.runButton?.image = #imageLiteral(resourceName: "StopTemplate")
        case .running(_):
            self.runButton?.isEnabled = true
            self.runButton?.image = #imageLiteral(resourceName: "StopTemplate")
        case .stopping(_, then: .restart):
            self.runButton?.isEnabled = true
            self.runButton?.image = #imageLiteral(resourceName: "StopTemplate")
        case .stopping(_, then: _):
            self.runButton?.isEnabled = false
            self.runButton?.image = #imageLiteral(resourceName: "StopTemplate")
        case .failedBenchmark:
            self.runButton?.image = #imageLiteral(resourceName: "RunTemplate")
            self.runButton?.isEnabled = true
        }
    }
}

extension AttabenchDocument {
    override class var readableTypes: [String] { return [UTI.attabench, UTI.attaresult] }
    override class var writableTypes: [String] { return [UTI.attaresult] }
    override class var autosavesInPlace: Bool { return true }

    override func data(ofType typeName: String) throws -> Data {
        switch typeName {
        case UTI.attaresult:
            return try JSONEncoder().encode(model.value)
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }
    }
    
    func readAttaresult(_ data: Data) throws {
        self.model.value = try JSONDecoder().decode(Attaresult.self, from: data)
        self.theme.value = BenchmarkTheme.Predefined.theme(named: self.model.value.themeName.value) ?? BenchmarkTheme.Predefined.screen
    }

    override func read(from url: URL, ofType typeName: String) throws {
        switch typeName {
        case UTI.attaresult:
            try self.readAttaresult(try Data(contentsOf: url))
            if let url = model.value.benchmarkURL.value {
                do {
                    log(.status, "Loading \(FileManager().displayName(atPath: url.path))")
                    self.state = .loading(try BenchmarkProcess(url: url, command: .list, delegate: self, on: .main))
                }
                catch {
                    log(.status, "Failed to load benchmark: \(error.localizedDescription)")
                    self.state = .failedBenchmark
                }
            }
            else {
                self.state = .noBenchmark
            }
        case UTI.attabench:
            log(.status, "Loading \(FileManager().displayName(atPath: url.path))")
            do {
                self.isDraft = true
                self.fileType = UTI.attaresult
                self.fileURL = nil
                self.fileModificationDate = nil
                self.displayName = url.deletingPathExtension().lastPathComponent
                self.model.value = Attaresult()
                self.model.value.benchmarkURL.value = url
                self.state = .loading(try BenchmarkProcess(url: url, command: .list, delegate: self, on: .main))
            }
            catch {
                log(.status, "Failed to load benchmark: \(error.localizedDescription)")
                self.state = .failedBenchmark
                throw error
            }
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }
    }
}

extension AttabenchDocument {
    //MARK: Logging & Status Messages

    enum LogKind {
        case standardOutput
        case standardError
        case status
    }
    func log(_ kind: LogKind, _ text: String) {
        let attributes: [NSAttributedString.Key: Any]
        switch kind {
        case .standardOutput: attributes = ConsoleAttributes.standardOutput
        case .standardError: attributes = ConsoleAttributes.standardError
        case .status: attributes = ConsoleAttributes.statusMessage
        }
        let atext = NSAttributedString(string: text, attributes: attributes)
        if let textView = self.consoleTextView {
            if !textView.textStorage!.string.hasSuffix("\n") {
                textView.textStorage!.mutableString.append("\n")
            }
            textView.textStorage!.append(atext)
            textView.scrollToEndOfDocument(nil)
        }
        else if let pendingLog = self._log {
            if !pendingLog.string.hasSuffix("\n") {
                pendingLog.mutableString.append("\n")
            }
            pendingLog.append(atext)
        }
        else {
            _log = (atext.mutableCopy() as! NSMutableAttributedString)
        }
    }

    @IBAction func clearConsole(_ sender: Any) {
        _log = nil
        self.consoleTextView?.textStorage?.setAttributedString(NSAttributedString())
    }

    enum StatusUpdate {
        case immediate
        case lazy
    }
    func setStatus(_ kind: StatusUpdate, _ text: String) {
        self._status = text
        switch kind {
        case .immediate: self.statusLabel?.immediateStatus = text
        case .lazy: self.statusLabel?.lazyStatus = text
        }
    }
}

extension AttabenchDocument {
    //MARK: BenchmarkDelegate

    func benchmark(_ benchmark: BenchmarkProcess, didReceiveListOfTasks taskNames: [String]) {
        guard case .loading(let process) = state, process === benchmark else { benchmark.stop(); return }
        let fresh = Set(taskNames)
        let stale = Set(model.value.tasks.value.map { $0.name })
        let newTaskNames = fresh.subtracting(stale)
        let missingTaskNames = stale.subtracting(fresh)

        let newTasks = newTaskNames.map(Task.init)
        model.value.tasks.value.append(contentsOf:newTasks)
        
        let tasks = model.value.tasks.value
        for task in tasks {
            task.isRunnable.value = fresh.contains(task.name)
        }
        model.value.tasks.value = tasks
//        for task in model.value.tasks.value {
//            task.isRunnable.value = fresh.contains(task.name)
//        }

        log(.status, "Received \(model.value.tasks.value.count) task names (\(newTaskNames.count) new, \(missingTaskNames.count) missing).")
    }

    func benchmark(_ benchmark: BenchmarkProcess, willMeasureTask task: String, atSize size: Int) {
        guard case .running(let process) = state, process === benchmark else { benchmark.stop(); return }
        setStatus(.lazy, "Measuring size \(size.sizeLabel) for task \(task)")
    }

    func benchmark(_ benchmark: BenchmarkProcess, didMeasureTask task: String, atSize size: Int, withResult time: Time) {
        guard case .running(let process) = state, process === benchmark else { benchmark.stop(); return }
        pendingResults.append((task, size, time))
        processPendingResults.later()
        if pendingResults.count > 10000 {
            // Don't let reports swamp the run loop.
            log(.status, "Receiving reports too quickly; terminating benchmark.")
            log(.status, "Try selected larger sizes, or increasing the iteration count or minimum duration in Run Options.")
            stopMeasuring()
        }
    }

    func benchmark(_ benchmark: BenchmarkProcess, didPrintToStandardOutput line: String) {
        guard self.state.process === benchmark else { benchmark.stop(); return }
        log(.standardOutput, line)
    }

    func benchmark(_ benchmark: BenchmarkProcess, didPrintToStandardError line: String) {
        guard self.state.process === benchmark else { benchmark.stop(); return }
        log(.standardError, line)
    }

    func benchmark(_ benchmark: BenchmarkProcess, didFailWithError error: String) {
        guard self.state.process === benchmark else { return }
        log(.status, error)
        processDidStop(success: false)
    }

    func benchmarkDidStop(_ benchmark: BenchmarkProcess) {
        guard self.state.process === benchmark else { return }
        log(.status, "Process finished.")
        processDidStop(success: true)
    }
}

// MARK: - Popup buttons handlers

extension AttabenchDocument {
    
    @objc
    private func didSelectBand(_ sender: NSMenuItem) {
        guard
            let bandValue = sender.representedObject as? CurveBandValues,
            let band = bandValue.band
            else { return }
        
        model.value.centerBand.value = band
    }
    
    @objc
    private func didSelectErrorBand(_ sender: NSMenuItem) {
        guard
            let bandValue = sender.representedObject as? ErrorBandValues,
            let topBand = bandValue.top,
            let bottomBand = bandValue.bottom
            else { return }
        
        model.value.topBand.value = topBand
        model.value.bottomBand.value = bottomBand
    }
    
    @objc
    private func didSelectTheme(_ sender: NSMenuItem) {
        guard let theme = sender.representedObject as? BenchmarkTheme else { return }
        
        self.theme.value = theme
    }
    
    @objc
    private func didSelectMinimumSize(_ sender: NSMenuItem) {
        guard let lowerBound = sender.representedObject as? Int else { return }
        
        model.value.sizeScaleRange.lowerBound = lowerBound
    }
    
    @objc
    private func didSelectMaximumSize(_ sender: NSMenuItem) {
        guard let upperBound = sender.representedObject as? Int else { return }
        
        model.value.sizeScaleRange.upperBound = upperBound
    }

    @objc
    private func didSelectScaleRangeLowerBound(_ sender: NSMenuItem) {
        guard let lowerBound = sender.representedObject as? Int else { return }
        
        model.value.displaySizeScaleRange.lowerBound = lowerBound
    }
    
    @objc
    private func didSelectScaleRangeUpperBound(_ sender: NSMenuItem) {
        guard let upperBound = sender.representedObject as? Int else { return }
        
        model.value.displaySizeScaleRange.upperBound = upperBound
    }
    
    @objc
    private func didSelectDisplayTimeLowerBound(_ sender: NSMenuItem) {
        guard let lowerBound = sender.representedObject as? Time else { return }
        
        model.value.displayTimeRange.lowerBound = lowerBound
    }
    
    @objc
    private func didSelectDisplayTimeUpperBound(_ sender: NSMenuItem) {
        guard let upperBound = sender.representedObject as? Time else { return }
        
        model.value.displayTimeRange.upperBound = upperBound
    }
}

//MARK: - Start/stop

extension AttabenchDocument {
    
    func processDidStop(success: Bool) {
        if let activity = self.activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        refreshChart.nowIfNeeded()
        switch self.state {
        case .loading(_):
            self.state = success ? .idle : .failedBenchmark
        case .stopping(_, then: .idle):
            self.state = .idle
        case .stopping(_, then: .restart):
            self.state = .idle
            startMeasuring()
        case .stopping(_, then: .reload):
            _reload()
        default:
            self.state = .idle
        }
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return super.validateMenuItem(menuItem) }
        switch action {
        case #selector(AttabenchDocument.startStopAction(_:)):
            let startLabel = "Start Running"
            let stopLabel = "Stop Running"

            guard model.value.benchmarkURL.value != nil else { return false }
            switch self.state {
            case .noBenchmark:
                menuItem.title = startLabel
                return false
            case .idle:
                menuItem.title = startLabel
                return true
            case .failedBenchmark:
                menuItem.title = startLabel
                return false
            case .loading(_):
                menuItem.title = stopLabel
                return true
            case .waiting:
                menuItem.title = stopLabel
                return true
            case .running(_):
                menuItem.title = stopLabel
                return true
            case .stopping(_, then: .restart):
                menuItem.title = stopLabel
                return true
            case .stopping(_, then: _):
                menuItem.title = stopLabel
                return false
            }
        case #selector(AttabenchDocument.delete(_:)):
            return self.tasksTableView?.selectedRowIndexes.isEmpty == false
        default:
            return super.validateMenuItem(menuItem)
        }
    }
    
    @IBAction func delete(_ sender: AnyObject) {
        // FIXME this is horrible. Implement Undo etc.
        let tasks = (self.tasksTableView?.selectedRowIndexes ?? []).map { self.visibleTasks.value[$0] }
        
        let selectedSizeRange = model.value.selectedSizeRange.value
        for task in tasks {
            task.deleteResults(in: NSEvent.modifierFlags.contains(.shift) ? nil : selectedSizeRange)
            if !task.isRunnable.value && task.sampleCount.value == 0 {
                model.value.remove(task)
            }
        }
//
//        model.value.tasks.withTransaction {
//            for task in tasks {
//                task.deleteResults(in:
//                    NSEvent.modifierFlags.contains(.shift) ? nil : self.model.value.selectedSizeRange.value)
//                if !task.isRunnable.value && task.sampleCount.value == 0 {
//                    self.m.remove(task)
//                }
//            }
//        }
        self.refreshChart.now()
        self.updateChangeCount(.changeDone)
    }

    @IBAction func chooseBenchmark(_ sender: AnyObject) {
        guard let window = self.windowControllers.first?.window else { return }
        let openPanel = NSOpenPanel()
        openPanel.message = "This result file has no associated Attabench document. To add measurements, you need to select a benchmark file."
        openPanel.prompt = "Choose"
        openPanel.canChooseFiles = true
        openPanel.allowedFileTypes = [UTI.attabench]
        openPanel.treatsFilePackagesAsDirectories = false
        openPanel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            guard let url = openPanel.urls.first else { return }
            self.model.value.benchmarkURL.value = url
            self._reload()
        }
    }

    func _reload() {
        do {
            guard let url = model.value.benchmarkURL.value else { chooseBenchmark(self); return }
            log(.status, "Loading \(FileManager().displayName(atPath: url.path))")
            self.state = .loading(try BenchmarkProcess(url: url, command: .list, delegate: self, on: .main))
        }
        catch {
            log(.status, "Failed to load benchmark: \(error.localizedDescription)")
            self.state = .failedBenchmark
        }
    }

    @IBAction func reloadAction(_ sender: AnyObject) {
        switch state {
        case .noBenchmark:
            chooseBenchmark(sender)
        case .idle, .failedBenchmark, .waiting:
            _reload()
        case .running(let process):
            self.state = .stopping(process, then: .reload)
            process.stop()
        case .loading(let process):
            self.state = .stopping(process, then: .reload)
            process.stop()
        case .stopping(let process, then: _):
            self.state = .stopping(process, then: .reload)
        }
    }

    @IBAction func startStopAction(_ sender: AnyObject) {
        switch state {
        case .noBenchmark, .failedBenchmark:
            NSSound.beep()
        case .idle:
            guard !model.value.tasks.value.isEmpty else { return }
            self.startMeasuring()
        case .waiting:
            self.state = .idle
        case .running(_):
            stopMeasuring()
        case .loading(let process):
            self.state = .failedBenchmark
            process.stop()
        case .stopping(let process, then: .restart):
            self.state = .stopping(process, then: .idle)
        case .stopping(let process, then: .reload):
            self.state = .stopping(process, then: .idle)
        case .stopping(let process, then: .idle):
            self.state = .stopping(process, then: .restart)
        }
    }

    func stopMeasuring() {
        guard case .running(let process) = state else { return }
        self.state = .stopping(process, then: .idle)
        process.stop()
    }

    func startMeasuring() {
        guard let source = self.model.value.benchmarkURL.value else { log(.status, "Can't start measuring"); return }
        switch self.state {
        case .waiting, .idle: break
        default: return
        }
        let tasks = tasksToRun.value.map { $0.name }
        let sizes = self.model.value.selectedSizes.value.sorted()
        guard !tasks.isEmpty, !sizes.isEmpty else {
            self.state = .waiting
            return
        }

        log(.status, "\nRunning \(model.value.benchmarkDisplayName.value) with \(tasks.count) tasks at sizes from \(sizes.first!.sizeLabel) to \(sizes.last!.sizeLabel).")
        let options = RunOptions(tasks: tasks,
                                 sizes: sizes,
                                 iterations: model.value.iterations.value,
                                 minimumDuration: model.value.durationRange.value.lowerBound.seconds,
                                 maximumDuration: model.value.durationRange.value.upperBound.seconds)
        do {
            self.state = .running(try BenchmarkProcess(url: source, command: .run(options), delegate: self, on: .main))
            self.activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .automaticTerminationDisabled, .suddenTerminationDisabled],
                reason: "Benchmarking")
        }
        catch {
            self.log(.status, error.localizedDescription)
            self.state = .idle
        }
    }

    func runOptionsDidChange() {
        switch self.state {
        case .waiting:
            startMeasuring()
        case .running(let process):
            self.state = .stopping(process, then: .restart)
        default:
            break
        }
    }
}

//MARK: Size selection

extension AttabenchDocument {

    @IBAction func increaseMinScale(_ sender: AnyObject) {
        model.value.sizeScaleRange.lowerBound += 1
    }

    @IBAction func decreaseMinScale(_ sender: AnyObject) {
        model.value.sizeScaleRange.lowerBound -= 1
    }

    @IBAction func increaseMaxScale(_ sender: AnyObject) {
        model.value.sizeScaleRange.upperBound += 1
    }

    @IBAction func decreaseMaxScale(_ sender: AnyObject) {
        model.value.sizeScaleRange.upperBound -= 1
    }
}

//MARK: Chart rendering

extension AttabenchDocument {
    
    private func _refreshChart() {
        guard let chartView = self.chartView else { return }

        let allTasks = model.value.tasks.value
        let tasks = allTasks.filter { $0.checked.value }

        var options = BenchmarkChart.Options()
        options.amortizedTime = model.value.amortizedTime.value
        options.logarithmicSize = model.value.logarithmicSizeScale.value
        options.logarithmicTime = model.value.logarithmicTimeScale.value

        var sizeBounds: ClosedRange<Int>?
        if model.value.highlightSelectedSizeRange.value {
            let range = model.value.sizeScaleRange.value
            sizeBounds = (1 << range.lowerBound) ... (1 << range.upperBound)
        }
        if model.value.displayIncludeSizeScaleRange.value {
            let range = model.value.displaySizeScaleRange.value
            let bounds = (1 << range.lowerBound) ... (1 << range.upperBound)
            sizeBounds = sizeBounds?.union(bounds) ?? bounds
        }
        options.displaySizeRange = sizeBounds
        options.displayAllMeasuredSizes = model.value.displayIncludeAllMeasuredSizes.value
        
        if model.value.displayIncludeTimeRange.value {
            options.displayTimeRange = model.value.displayTimeRange.value
        }
        options.displayAllMeasuredTimes = model.value.displayIncludeAllMeasuredTimes.value

        options.band[.top] = model.value.topBand.value
        options.band[.center] = model.value.centerBand.value
        options.band[.bottom] = model.value.bottomBand.value

        chartView.chart = BenchmarkChart(title: "", tasks: tasks, options: options)
    }
}

extension AttabenchDocument: NSSplitViewDelegate {
    @IBAction func showHideLeftPane(_ sender: Any) {
        guard let pane = self.leftPane else { return }
        pane.isHidden = !pane.isHidden
    }

    @IBAction func showHideRightPane(_ sender: Any) {
        guard let pane = self.rightPane else { return }
        pane.isHidden = !pane.isHidden
    }

    @IBAction func showHideRunOptions(_ sender: NSButton) {
        guard let pane = self.runOptionsPane else { return }
        pane.isHidden = !pane.isHidden
    }
    @IBAction func showHideConsole(_ sender: NSButton) {
        guard let pane = self.consolePane else { return }
        pane.isHidden = !pane.isHidden
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        if subview === self.leftPane { return true }
        if subview === self.rightPane { return true }
        if subview === self.runOptionsPane { return true }
        if subview === self.consolePane { return true }
        return false
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView else { return }
        if splitView === rootSplitView {
            let state: NSControl.StateValue = splitView.isSubviewCollapsed(self.leftPane!) ? .off : .on
            if showLeftPaneButton!.state != state {
                showLeftPaneButton!.state = state
            }
        }
        if splitView === rootSplitView {
            let state: NSControl.StateValue = splitView.isSubviewCollapsed(self.rightPane!) ? .off : .on
            if showRightPaneButton!.state != state {
                showRightPaneButton!.state = state
            }
        }
        else if splitView === leftVerticalSplitView {
            let state: NSControl.StateValue = splitView.isSubviewCollapsed(self.runOptionsPane!) ? .off : .on
            if showRunOptionsButton!.state != state {
                showRunOptionsButton!.state = state
            }
        }
        else if splitView === middleSplitView {
            let state: NSControl.StateValue = splitView.isSubviewCollapsed(self.consolePane!) ? .off : .on
            if showConsoleButton!.state != state {
                showConsoleButton!.state = state
            }
        }
    }
    
    func splitView(_ splitView: NSSplitView, additionalEffectiveRectOfDividerAt dividerIndex: Int) -> NSRect {
        if splitView === middleSplitView, dividerIndex == 1 {
            let status = splitView.convert(self.statusLabel!.bounds, from: self.statusLabel!)
            let bar = splitView.convert(self.middleBar!.bounds, from: self.middleBar!)
            return CGRect(x: status.minX, y: bar.minY, width: status.width, height: bar.height)
        }
        return .zero
    }

}

extension AttabenchDocument {
    @IBAction func batchCheckboxAction(_ sender: NSButton) {
        let v = (sender.state != .off)
        self.visibleTasks.value.forEach { $0.checked.value = v }
    }
}

extension AttabenchDocument: NSTextFieldDelegate {
    
    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as AnyObject === self.taskFilterTextField else {
            return
        }
        let v = self.taskFilterTextField!.stringValue
        self.taskFilterString.value = v.isEmpty ? nil : v
    }
}

extension AttabenchDocument {
    //MARK: State restoration
    enum RestorationKey: String {
        case taskFilterString
    }

    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        coder.encode(self.taskFilterString.value, forKey: RestorationKey.taskFilterString.rawValue)
    }

    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        self.taskFilterString.value = coder.decodeObject(forKey: RestorationKey.taskFilterString.rawValue) as? String
    }
}
