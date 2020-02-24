// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import Combine
import BenchmarkModel
import BenchmarkRunner
import BenchmarkCharts
import BenchmarkIPC

enum ConsoleAttributes {
    private static let indentedParagraphStyle: NSParagraphStyle = {
        let style = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        style.headIndent = 12
        style.firstLineHeadIndent = 12
        return style
    }()
    static let standardOutput: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor.tertiaryLabelColor,
        .paragraphStyle: indentedParagraphStyle
    ]
    static let standardError: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .bold),
        .foregroundColor: NSColor.secondaryLabelColor,
        .paragraphStyle: indentedParagraphStyle
    ]
    static let statusMessage: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: NSParagraphStyle.default
    ]
    static let errorMessage: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .bold),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: NSParagraphStyle.default
    ]
}

class AttabenchDocument: NSDocument, BenchmarkDelegate {

    private enum State {
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

    override var windowNibName: NSNib.Name? {
        // Returns the nib file name of the document
        // If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this property and override -makeWindowControllers instead.
        return "AttabenchDocument"
    }

    @IBOutlet var runButton: NSButton!
    @IBOutlet var minimumSizeButton: NSPopUpButton!
    @IBOutlet var maximumSizeButton: NSPopUpButton!
    @IBOutlet var rootSplitView: NSSplitView!

    @IBOutlet var leftPane: NSVisualEffectView!
    @IBOutlet var leftVerticalSplitView: NSSplitView!
    @IBOutlet var tasksTableView: NSTableView!
    @IBOutlet var leftBar: ColoredView!
    @IBOutlet var batchCheckbox: NSButtonCell!
    @IBOutlet var taskFilterTextField: NSSearchField!
    @IBOutlet var showRunOptionsButton: NSButton!
    @IBOutlet var runOptionsPane: ColoredView!
    @IBOutlet var iterationsField: NSTextField!
    @IBOutlet var iterationsStepper: NSStepper!
    @IBOutlet var minimumDurationField: NSTextField!
    @IBOutlet var maximumDurationField: NSTextField!

    @IBOutlet var middleSplitView: NSSplitView!
    @IBOutlet var chartView: ChartView!
    @IBOutlet var middleBar: ColoredView!
    @IBOutlet var showLeftPaneButton: NSButton!
    @IBOutlet var showConsoleButton: NSButton!
    @IBOutlet var statusLabel: StatusLabel!
    @IBOutlet var showRightPaneButton: NSButton!
    @IBOutlet var consolePane: NSView!
    @IBOutlet var consoleTextView: NSTextView!

    @IBOutlet var rightPane: ColoredView!
    
    @IBOutlet var themePopUpButton: NSPopUpButton!
    @IBOutlet var amortizedCheckbox: NSButton!
    @IBOutlet var logarithmicSizeCheckbox: NSButton!
    @IBOutlet var logarithmicTimeCheckbox: NSButton!

    @IBOutlet var centerBandPopUpButton: NSPopUpButton!
    @IBOutlet var errorBandPopUpButton: NSPopUpButton!
    
    @IBOutlet var highlightSelectedSizeRangeCheckbox: NSButton!
    @IBOutlet var displayIncludeAllMeasuredSizesCheckbox: NSButton!
    @IBOutlet var displayIncludeSizeScaleRangeCheckbox: NSButton!
    @IBOutlet var displaySizeScaleRangeMinPopUpButton: NSPopUpButton!
    @IBOutlet var displaySizeScaleRangeMaxPopUpButton: NSPopUpButton!

    @IBOutlet var displayIncludeAllMeasuredTimesCheckbox: NSButton!
    @IBOutlet var displayIncludeTimeRangeCheckbox: NSButton!
    @IBOutlet var displayTimeRangeMinPopUpButton: NSPopUpButton!
    @IBOutlet var displayTimeRangeMaxPopUpButton: NSPopUpButton!

    @IBOutlet var progressRefreshIntervalField: NSTextField!
    @IBOutlet var chartRefreshIntervalField: NSTextField!

    var model = Attaresult() {
        didSet {
            guard !windowControllers.isEmpty else { return }
            bind(model: model)
        }
    }
    
    private var state: State = .noBenchmark {
        didSet { stateDidChange(from: oldValue, to: state) }
    }
    
    private var activity: NSObjectProtocol? // Preventing system sleep

    private let taskFilterString = CurrentValueSubject<String?, Never>(nil)
    private let taskFilter = CurrentValueSubject<TaskFilter, Never>(TaskFilter(nil))
    
    let visibleTasks = CurrentValueSubject<[Task], Never>([])
    private let checkedTasks = CurrentValueSubject<[Task], Never>([])
    private let tasksToRun = CurrentValueSubject<[Task], Never>([])

    private let batchCheckboxState = CurrentValueSubject<NSControl.StateValue, Never>(.on)

    private let theme = CurrentValueSubject<BenchmarkTheme, Never>(BenchmarkTheme.Predefined.screen)

    private lazy var refreshChart = RateLimiter(maxDelay: 5, async: true) { [unowned self] in self._refreshChart() }
    private var tasksTableViewController: CombineTableViewController<Task, TaskCellView>?

    private var pendingResults: [(task: String, size: Int, time: Time)] = []
    private lazy var processPendingResults = RateLimiter(maxDelay: 0.2) { [unowned self] in
        for (task, size, time) in self.pendingResults {
            self.model.addMeasurement(time, forTask: task, size: size)
        }
        self.pendingResults = []
        self.updateChangeCount(.changeDone)
        self.refreshChart.later()
    }

    private var logBuffer: NSMutableAttributedString? = nil
    private var pendindgStatus: String = "Ready"

    private var cancellables = Set<AnyCancellable>()
    private var modelCancellables = Set<AnyCancellable>()
        
    override init() {
        super.init()
        
        privateInit()
    }

    deinit {
        // TODO: EK - figure out why we need to update state on dealloc
        self.state = .idle
    }

    private func privateInit() {
        taskFilterString
            .map(TaskFilter.init)
            .subscribe(taskFilter)
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
            .combineLatest(checkedCount) { visibleCount, checkedCount in
                if visibleCount == checkedCount { return .on }
                if checkedCount == 0 { return .off }
                return .mixed
            }
            .subscribe(batchCheckboxState)
            .store(in: &cancellables)
    }
    
    // FIXME: EK - Holy moly, this is a big one.
    private func bind(model: Attaresult) {
        modelCancellables = []
        
        model.tasks
            .combineLatest(taskFilter) { tasks, filter in
                tasks.filter(filter.test)
            }
            .subscribe(visibleTasks)
            .store(in: &modelCancellables)
        
        // TODO: EK - why data flows this way? Shouldn't it be the other way around?
        theme.map(\.name).subscribe(model.themeName).store(in: &modelCancellables)

        Publishers
            .Merge(
                tasksToRun.map({ _ in Void() }),
                model.runOptionsTick
            )
            .sink { [unowned self] in
                self.updateChangeCount(.changeDone)
                self.runOptionsDidChange()
            }
            .store(in: &modelCancellables)
        
        Publishers
            .Merge3(
                checkedTasks.map({ _ in Void() }),
                model.runOptionsTick,
                model.chartOptionsTick
            )
            .sink { [unowned self] in
                self.updateChangeCount(.changeDone)
                self.refreshChart.now()
            }
            .store(in: &modelCancellables)

        model.progressRefreshInterval
            .sink { [unowned self] interval in
                self.statusLabel.refreshRate = interval.seconds
                self.processPendingResults.maxDelay = interval.seconds
            }
            .store(in: &modelCancellables)
        
        model.chartRefreshInterval
            .sink { [unowned self] interval in
                self.refreshChart.maxDelay = interval.seconds
            }
            .store(in: &modelCancellables)
        
        let iterations = model.iterations

        iterations
            .sink { [unowned self] iterations in
                self.iterationsField.stringValue = String(iterations)
            }
            .store(in: &modelCancellables)

        Binding.bind(
            control: iterationsStepper,
            toView: { $1.intValue = Int32($0) },
            fromView: { [unowned model] in model.iterations.value = $0 },
            controlValue: { $0.objectValue as? Int },
            in: iterations
        ).store(in: &modelCancellables)
        
        Binding.bind(
            control: minimumDurationField,
            toView: { $1.stringValue = String($0) },
            fromView: { [unowned model] in model.durationRange.lowerBound = $0 },
            controlValue: { Time($0.stringValue) },
            in: model.durationRange.lowerBoundPublisher
        ).store(in: &modelCancellables)
        
        Binding.bind(
            control: maximumDurationField,
            toView: { $1.stringValue = String($0) },
            fromView: { [unowned model] in model.durationRange.upperBound = $0 },
            controlValue: { Time($0.stringValue) },
            in: model.durationRange.upperBoundPublisher
        ).store(in: &modelCancellables)
        
        Binding.bind(amortizedCheckbox, with: model.amortizedTime)
            .store(in: &modelCancellables)
        
        Binding.bind(logarithmicSizeCheckbox, with: model.logarithmicSizeScale)
            .store(in: &modelCancellables)

        Binding.bind(logarithmicTimeCheckbox, with: model.logarithmicTimeScale)
            .store(in: &modelCancellables)

        Binding.bind(progressRefreshIntervalField, with:  model.progressRefreshInterval)
            .store(in: &modelCancellables)

        Binding
            .bind(chartRefreshIntervalField, with: model.chartRefreshInterval)
            .store(in: &modelCancellables)

        let bandChoices: [(title: String, value: CurveBandValues)] = [
            ("None", CurveBandValues.none),
            ("Minimum", CurveBandValues.minimum),
            ("Average", CurveBandValues.average),
            ("Maximum", CurveBandValues.maximum),
            ("Sample Size", CurveBandValues.count),
        ]
        MenuBinding.bind(
            button: centerBandPopUpButton,
            stream: model.centerBand.map(CurveBandValues.init),
            items: bandChoices,
            onSelect: { [unowned model] bandValue in
                guard let band = bandValue.band else { return }
                model.centerBand.value = band
            }
        ).store(in: &modelCancellables)
        
        let availableErrorBands: [(title: String, value: ErrorBandValues)] = [
            ("None", ErrorBandValues.none),
            ("Maximum", ErrorBandValues.maximum),
            ("μ + σ", ErrorBandValues.sigma1),
            ("μ + 2σ", ErrorBandValues.sigma2),
            ("μ + 3σ", ErrorBandValues.sigma3),
        ]
        let topBand = model.topBand
        let bottomBand = model.bottomBand
        let errorBand = topBand
            .combineLatest(bottomBand) { top, bottom in
                ErrorBandValues(top: top, bottom: bottom)
            }
        MenuBinding.bind(
            button: errorBandPopUpButton,
            stream: errorBand,
            items: availableErrorBands,
            onSelect: { [unowned model] bandValue in
                guard
                    let topBand = bandValue.top,
                    let bottomBand = bandValue.bottom
                    else { return }
                
                model.topBand.value = topBand
                model.bottomBand.value = bottomBand

            }
        ).store(in: &modelCancellables)

        let availableThemes = BenchmarkTheme.Predefined.themes.map { (title: $0.name, value: $0) }
        MenuBinding.bind(
            button: themePopUpButton,
            stream: theme,
            items: availableThemes,
            onSelect: { [unowned self] theme in
                self.theme.value = theme
            }
        ).store(in: &modelCancellables)

        let sizeChoices: [(title: String, value: Int)]
            = (0 ... Attaresult.largestPossibleSizeScale).map { ((1 << $0).sizeLabel, $0) }
        let lowerBoundSizeChoices = sizeChoices.map { (title: "\($0.0) ≤", value: $0.1) }
        let upperBoundSizeChoices = sizeChoices.map { (title: "≤ \($0.0)", value: $0.1) }
        
        MenuBinding.bind(
            button: minimumSizeButton,
            stream: model.sizeScaleRange.lowerBoundPublisher,
            items: lowerBoundSizeChoices,
            onSelect: { [unowned model] lowerBound in
                model.sizeScaleRange.lowerBound = lowerBound
            }
        ).store(in: &modelCancellables)

        MenuBinding.bind(
            button: maximumSizeButton,
            stream: model.sizeScaleRange.upperBoundPublisher,
            items: upperBoundSizeChoices,
            onSelect: { [unowned model] upperBound in
                model.sizeScaleRange.upperBound = upperBound
            }
        ).store(in: &modelCancellables)

        Binding.bind(highlightSelectedSizeRangeCheckbox, with: model.highlightSelectedSizeRange)
            .store(in: &modelCancellables)
        
        Binding.bind(displayIncludeAllMeasuredSizesCheckbox, with: model.displayIncludeAllMeasuredSizes)
            .store(in: &modelCancellables)

        Binding.bind(displayIncludeSizeScaleRangeCheckbox, with: model.displayIncludeSizeScaleRange)
            .store(in: &modelCancellables)

        MenuBinding.bind(
            button: displaySizeScaleRangeMinPopUpButton,
            stream: model.displaySizeScaleRange.lowerBoundPublisher,
            items: lowerBoundSizeChoices,
            onSelect: { [unowned model] lowerBound in
                model.displaySizeScaleRange.lowerBound = lowerBound
            }
        ).store(in: &modelCancellables)
        
        model.displayIncludeSizeScaleRange
            .sink { [unowned self] enabled in
                self.displaySizeScaleRangeMinPopUpButton.isEnabled = enabled
            }
            .store(in: &modelCancellables)

        MenuBinding.bind(
            button: displaySizeScaleRangeMaxPopUpButton,
            stream: model.displaySizeScaleRange.upperBoundPublisher,
            items: upperBoundSizeChoices,
            onSelect: { [unowned model] upperBound in
                model.displaySizeScaleRange.upperBound = upperBound
            }
        ).store(in: &modelCancellables)

        model.displayIncludeSizeScaleRange
            .sink { [unowned self] enabled in
                self.displaySizeScaleRangeMaxPopUpButton.isEnabled = enabled
            }
            .store(in: &modelCancellables)
        
        Binding.bind(displayIncludeAllMeasuredTimesCheckbox, with: model.displayIncludeAllMeasuredTimes)
            .store(in: &modelCancellables)

        Binding.bind(displayIncludeTimeRangeCheckbox, with: model.displayIncludeTimeRange)
            .store(in: &modelCancellables)
        
        var timeChoices: [(title: String, value: Time)] = []
        var time = Time(picoseconds: 1)
        for _ in 0 ..< 20 {
            timeChoices.append(("\(time)", time))
            time = 10 * time
        }
        
        MenuBinding.bind(
            button: displayTimeRangeMinPopUpButton,
            stream: model.displayTimeRange.lowerBoundPublisher,
            items: timeChoices,
            onSelect: { [unowned model] lowerBound in
                model.displayTimeRange.lowerBound = lowerBound
            }
        ).store(in: &modelCancellables)
        
        model.displayIncludeTimeRange
            .sink { [unowned self] enabled in
                self.displayTimeRangeMinPopUpButton.isEnabled = enabled
            }
            .store(in: &modelCancellables)

        MenuBinding.bind(
            button: displayTimeRangeMaxPopUpButton,
            stream: model.displayTimeRange.upperBoundPublisher,
            items: timeChoices,
            onSelect: { [unowned model] upperBound in
                model.displayTimeRange.upperBound = upperBound
            }
        ).store(in: &modelCancellables)
        
        model.displayIncludeTimeRange
            .sink { [unowned self] enabled in
                self.displayTimeRangeMaxPopUpButton.isEnabled = enabled
            }
            .store(in: &modelCancellables)
    }
    
    override func windowControllerDidLoadNib(_ windowController: NSWindowController) {
        super.windowControllerDidLoadNib(windowController)
        
        consoleTextView.textStorage?.setAttributedString(logBuffer ?? NSAttributedString())
        
        let tasksTVC = CombineTableViewController<Task, TaskCellView>(tableView: tasksTableView, contents: visibleTasks) { [unowned self] cell, item in
            cell.task = item
            cell.context = self
        }
        tasksTableViewController = tasksTVC
        tasksTableView.delegate = tasksTVC
        tasksTableView.dataSource = tasksTVC
        statusLabel.immediateStatus = pendindgStatus
        chartView.documentBasename = displayName

        theme.subscribe(chartView.theme).store(in: &cancellables)
        
        batchCheckboxState
            .sink { [unowned self] state in
                self.batchCheckbox.state = state
            }
            .store(in: &cancellables)

        taskFilterString
            .sink { [unowned self] filter in
                guard let field = self.taskFilterTextField, field.stringValue != filter else { return }
                self.taskFilterTextField.stringValue = filter ?? ""
            }
            .store(in: &cancellables)

        bind(model: model)
        
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
    }

    private func stateDidChange(from old: State, to new: State) {
        switch old {
        case .loading(let process):
            process.stop()
        case .running(let process):
            process.stop()
        default:
            break
        }

        let name = model.benchmarkDisplayName.value

        switch new {
        case .noBenchmark:
            setStatus(.immediate, "Attabench document cannot be found; can't take new measurements")
        case .idle:
            setStatus(.immediate, "Ready")
        case .loading(_):
            setStatus(.immediate, "Loading \(name)...")
        case .waiting:
            setStatus(.immediate, "No executable tasks selected, pausing")
        case .running(_):
            setStatus(.immediate, "Starting \(name)...")
        case .stopping(_, then: .restart):
            setStatus(.immediate, "Restarting \(name)...")
        case .stopping(_, then: _):
            setStatus(.immediate, "Stopping \(name)...")
        case .failedBenchmark:
            setStatus(.immediate, "Failed")
        }
        refreshRunButton()
    }

    func refreshRunButton() {
        guard runButton != nil else { return }

        // FIXME: EK - get rid of image literals
        switch state {
        case .noBenchmark:
            runButton.isEnabled = false
            runButton.image = #imageLiteral(resourceName: "RunTemplate")
        case .idle:
            runButton.isEnabled = true
            runButton.image = #imageLiteral(resourceName: "RunTemplate")
        case .loading(_):
            runButton.isEnabled = true
            runButton.image = #imageLiteral(resourceName: "StopTemplate")
        case .waiting:
            runButton.isEnabled = true
            runButton.image = #imageLiteral(resourceName: "StopTemplate")
        case .running(_):
            runButton.isEnabled = true
            runButton.image = #imageLiteral(resourceName: "StopTemplate")
        case .stopping(_, then: .restart):
            runButton.isEnabled = true
            runButton.image = #imageLiteral(resourceName: "StopTemplate")
        case .stopping(_, then: _):
            runButton.isEnabled = false
            runButton.image = #imageLiteral(resourceName: "StopTemplate")
        case .failedBenchmark:
            runButton.image = #imageLiteral(resourceName: "RunTemplate")
            runButton.isEnabled = true
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
            return try JSONEncoder().encode(model)
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }
    }
    
    func readAttaresult(_ data: Data) throws {
        model = try JSONDecoder().decode(Attaresult.self, from: data)
        theme.value = BenchmarkTheme.Predefined.theme(named: self.model.themeName.value) ?? BenchmarkTheme.Predefined.screen
    }

    override func read(from url: URL, ofType typeName: String) throws {
        switch typeName {
        case UTI.attaresult:
            try self.readAttaresult(try Data(contentsOf: url))
            if let url = model.benchmarkURL.value {
                do {
                    log(.status, "Loading \(FileManager().displayName(atPath: url.path))")
                    state = .loading(try BenchmarkProcess(url: url, command: .list, delegate: self, on: .main))
                } catch {
                    log(.status, "Failed to load benchmark: \(error.localizedDescription)")
                    state = .failedBenchmark
                }
            } else {
                state = .noBenchmark
            }
        case UTI.attabench:
            log(.status, "Loading \(FileManager().displayName(atPath: url.path))")
            do {
                self.isDraft = true
                self.fileType = UTI.attaresult
                self.fileURL = nil
                self.fileModificationDate = nil
                self.displayName = url.deletingPathExtension().lastPathComponent
                model = Attaresult()
                model.benchmarkURL.value = url
                state = .loading(try BenchmarkProcess(url: url, command: .list, delegate: self, on: .main))
            } catch {
                log(.status, "Failed to load benchmark: \(error.localizedDescription)")
                state = .failedBenchmark
                throw error
            }
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }
    }
}

//MARK: - Logging & Status Messages

extension AttabenchDocument {

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
        
        let attributedMessage = NSAttributedString(string: text, attributes: attributes)
        if let textView = self.consoleTextView {
            if !textView.textStorage!.string.hasSuffix("\n") {
                textView.textStorage!.mutableString.append("\n")
            }
            textView.textStorage!.append(attributedMessage)
            textView.scrollToEndOfDocument(nil)
        } else if let pendingLog = logBuffer {
            if !pendingLog.string.hasSuffix("\n") {
                pendingLog.mutableString.append("\n")
            }
            pendingLog.append(attributedMessage)
        } else {
            logBuffer = (attributedMessage.mutableCopy() as! NSMutableAttributedString)
        }
    }

    @IBAction func clearConsole(_ sender: Any) {
        logBuffer = nil
        consoleTextView.textStorage?.setAttributedString(NSAttributedString())
    }

    enum StatusUpdate {
        case immediate
        case lazy
    }
    
    func setStatus(_ kind: StatusUpdate, _ text: String) {
        pendindgStatus = text

        guard statusLabel != nil else { return }
        
        switch kind {
        case .immediate: statusLabel.immediateStatus = text
        case .lazy: statusLabel.lazyStatus = text
        }
    }
}

//MARK: - BenchmarkDelegate

extension AttabenchDocument {

    func benchmark(_ benchmark: BenchmarkProcess, didReceiveListOfTasks taskNames: [String]) {
        guard case .loading(let process) = state, process === benchmark else { benchmark.stop(); return }
        let fresh = Set(taskNames)
        let stale = Set(model.tasks.value.map { $0.name })
        let newTaskNames = fresh.subtracting(stale)
        let missingTaskNames = stale.subtracting(fresh)

        let newTasks = newTaskNames.map(Task.init)
        model.tasks.value.append(contentsOf:newTasks)
        
        let tasks = model.tasks.value
        for task in tasks {
            task.isRunnable.value = fresh.contains(task.name)
        }
        model.tasks.value = tasks

        log(.status, "Received \(model.tasks.value.count) task names (\(newTaskNames.count) new, \(missingTaskNames.count) missing).")
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

//MARK: - Start/stop

extension AttabenchDocument {
    
    func processDidStop(success: Bool) {
        if let activity = self.activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        refreshChart.nowIfNeeded()
        switch state {
        case .loading(_):
            state = success ? .idle : .failedBenchmark
        case .stopping(_, then: .idle):
            state = .idle
        case .stopping(_, then: .restart):
            state = .idle
            startMeasuring()
        case .stopping(_, then: .reload):
            _reload()
        default:
            state = .idle
        }
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return super.validateMenuItem(menuItem) }
        switch action {
        case #selector(AttabenchDocument.startStopAction(_:)):
            let startLabel = "Start Running"
            let stopLabel = "Stop Running"

            guard model.benchmarkURL.value != nil else { return false }
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
            return self.tasksTableView.selectedRowIndexes.isEmpty == false
        default:
            return super.validateMenuItem(menuItem)
        }
    }
    
    @IBAction func delete(_ sender: AnyObject) {
        // FIXME this is horrible. Implement Undo etc.
        let tasks = tasksTableView.selectedRowIndexes.map { visibleTasks.value[$0] }
        
        let selectedSizeRange = model.selectedSizeRange.value
        for task in tasks {
            task.deleteResults(in: NSEvent.modifierFlags.contains(.shift) ? nil : selectedSizeRange)
            if !task.isRunnable.value && task.sampleCount.value == 0 {
                model.remove(task)
            }
        }

        refreshChart.now()
        updateChangeCount(.changeDone)
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
            self.model.benchmarkURL.value = url
            self._reload()
        }
    }

    func _reload() {
        do {
            guard let url = model.benchmarkURL.value else { chooseBenchmark(self); return }
            log(.status, "Loading \(FileManager().displayName(atPath: url.path))")
            state = .loading(try BenchmarkProcess(url: url, command: .list, delegate: self, on: .main))
        } catch {
            log(.status, "Failed to load benchmark: \(error.localizedDescription)")
            state = .failedBenchmark
        }
    }

    @IBAction func reloadAction(_ sender: AnyObject) {
        switch state {
        case .noBenchmark:
            chooseBenchmark(sender)
        case .idle, .failedBenchmark, .waiting:
            _reload()
        case .running(let process):
            state = .stopping(process, then: .reload)
            process.stop()
        case .loading(let process):
            state = .stopping(process, then: .reload)
            process.stop()
        case .stopping(let process, then: _):
            state = .stopping(process, then: .reload)
        }
    }

    @IBAction func startStopAction(_ sender: AnyObject) {
        switch state {
        case .noBenchmark, .failedBenchmark:
            NSSound.beep()
        case .idle:
            guard !model.tasks.value.isEmpty else { return }
            startMeasuring()
        case .waiting:
            state = .idle
        case .running(_):
            stopMeasuring()
        case .loading(let process):
            state = .failedBenchmark
            process.stop()
        case .stopping(let process, then: .restart):
            state = .stopping(process, then: .idle)
        case .stopping(let process, then: .reload):
            state = .stopping(process, then: .idle)
        case .stopping(let process, then: .idle):
            state = .stopping(process, then: .restart)
        }
    }

    func stopMeasuring() {
        guard case .running(let process) = state else { return }
        state = .stopping(process, then: .idle)
        process.stop()
    }

    func startMeasuring() {
        guard let source = model.benchmarkURL.value else { log(.status, "Can't start measuring"); return }
        switch state {
        case .waiting, .idle: break
        default: return
        }
        
        let tasks = tasksToRun.value.map { $0.name }
        let sizes = model.selectedSizes.value.sorted()
        guard !tasks.isEmpty, !sizes.isEmpty else {
            state = .waiting
            return
        }

        log(.status, "\nRunning \(model.benchmarkDisplayName.value) with \(tasks.count) tasks at sizes from \(sizes.first!.sizeLabel) to \(sizes.last!.sizeLabel).")
        let options = RunOptions(tasks: tasks,
                                 sizes: sizes,
                                 iterations: model.iterations.value,
                                 minimumDuration: model.durationRange.value.lowerBound.seconds,
                                 maximumDuration: model.durationRange.value.upperBound.seconds)
        do {
            state = .running(try BenchmarkProcess(url: source, command: .run(options), delegate: self, on: .main))
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .automaticTerminationDisabled, .suddenTerminationDisabled],
                reason: "Benchmarking")
        } catch {
            log(.status, error.localizedDescription)
            state = .idle
        }
    }

    func runOptionsDidChange() {
        switch state {
        case .waiting:
            startMeasuring()
        case .running(let process):
            state = .stopping(process, then: .restart)
        default:
            break
        }
    }
}

//MARK: - Size selection

extension AttabenchDocument {
    @IBAction func increaseMinScale(_ sender: AnyObject) {
        model.sizeScaleRange.lowerBound += 1
    }

    @IBAction func decreaseMinScale(_ sender: AnyObject) {
        model.sizeScaleRange.lowerBound -= 1
    }

    @IBAction func increaseMaxScale(_ sender: AnyObject) {
        model.sizeScaleRange.upperBound += 1
    }

    @IBAction func decreaseMaxScale(_ sender: AnyObject) {
        model.sizeScaleRange.upperBound -= 1
    }
}

//MARK: - Chart rendering

extension AttabenchDocument {
    
    private func _refreshChart() {
        guard let chartView = self.chartView else { return }

        let allTasks = model.tasks.value
        let tasks = allTasks.filter { $0.checked.value }

        var options = BenchmarkChart.Options()
        options.amortizedTime = model.amortizedTime.value
        options.logarithmicSize = model.logarithmicSizeScale.value
        options.logarithmicTime = model.logarithmicTimeScale.value

        var sizeBounds: ClosedRange<Int>?
        if model.highlightSelectedSizeRange.value {
            let range = model.sizeScaleRange.value
            sizeBounds = (1 << range.lowerBound) ... (1 << range.upperBound)
        }
        if model.displayIncludeSizeScaleRange.value {
            let range = model.displaySizeScaleRange.value
            let bounds = (1 << range.lowerBound) ... (1 << range.upperBound)
            sizeBounds = sizeBounds?.union(bounds) ?? bounds
        }
        options.displaySizeRange = sizeBounds
        options.displayAllMeasuredSizes = model.displayIncludeAllMeasuredSizes.value
        
        if model.displayIncludeTimeRange.value {
            options.displayTimeRange = model.displayTimeRange.value
        }
        options.displayAllMeasuredTimes = model.displayIncludeAllMeasuredTimes.value

        options.band[.top] = model.topBand.value
        options.band[.center] = model.centerBand.value
        options.band[.bottom] = model.bottomBand.value

        chartView.chart = BenchmarkChart(title: "", tasks: tasks, options: options)
    }
}

// MARK: - Splitview

extension AttabenchDocument: NSSplitViewDelegate {

    @IBAction func showHideLeftPane(_ sender: Any) {
        leftPane.isHidden.toggle()
    }

    @IBAction func showHideRightPane(_ sender: Any) {
        rightPane.isHidden.toggle()
    }

    @IBAction func showHideRunOptions(_ sender: NSButton) {
        runOptionsPane.isHidden.toggle()
    }
    
    @IBAction func showHideConsole(_ sender: NSButton) {
        consolePane.isHidden.toggle()
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        if subview === leftPane { return true }
        if subview === rightPane { return true }
        if subview === runOptionsPane { return true }
        if subview === consolePane { return true }
        return false
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView else { return }
        
        switch splitView {
        case rootSplitView:
            showLeftPaneButton.state = splitView.isSubviewCollapsed(leftPane) ? .off : .on
            showRightPaneButton.state = splitView.isSubviewCollapsed(rightPane) ? .off : .on
        case leftVerticalSplitView:
            showRunOptionsButton.state = splitView.isSubviewCollapsed(runOptionsPane) ? .off : .on
        case middleSplitView:
            showConsoleButton.state = splitView.isSubviewCollapsed(consolePane) ? .off : .on
        default:
            fatalError("Unknown slplit view")
        }
    }
    
    func splitView(_ splitView: NSSplitView, additionalEffectiveRectOfDividerAt dividerIndex: Int) -> NSRect {
        if splitView === middleSplitView, dividerIndex == 1 {
            let status = splitView.convert(statusLabel.bounds, from: statusLabel)
            let bar = splitView.convert(middleBar.bounds, from: middleBar)
            return CGRect(x: status.minX, y: bar.minY, width: status.width, height: bar.height)
        }
        return .zero
    }

}

extension AttabenchDocument {
    @IBAction func batchCheckboxAction(_ sender: NSButton) {
        let isChecked = sender.state != .off
        visibleTasks.value.forEach { $0.checked.value = isChecked }
    }
}

extension AttabenchDocument: NSTextFieldDelegate {
    
    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as AnyObject === taskFilterTextField else {
            return
        }
        let filterValue = taskFilterTextField.stringValue
        taskFilterString.value = filterValue.isEmpty ? nil : filterValue
    }
}

//MARK: - State restoration

extension AttabenchDocument {
    enum RestorationKey: String {
        case taskFilterString
    }

    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        coder.encode(taskFilterString.value, forKey: RestorationKey.taskFilterString.rawValue)
    }

    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        taskFilterString.value = coder.decodeObject(forKey: RestorationKey.taskFilterString.rawValue) as? String
    }
}
