// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import Combine
import BenchmarkModel
import BenchmarkCharts

@IBDesignable
class ChartView: NSView {
    
    var documentBasename: String = "Benchmark"

    override var frame: NSRect {
        didSet {
            if theme.value.imageSize == nil {
                render()
            }
        }
    }
    
    let theme = CurrentValueSubject<BenchmarkTheme, Never>(BenchmarkTheme.Predefined.screen)

    var chart: BenchmarkChart? = nil {
        didSet { render() }
    }

    var image: NSImage? = nil {
        didSet { needsDisplay = true }
    }

    @IBInspectable
    var backgroundColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    var downEvent: NSEvent? = nil

    private var cancellables: Set<AnyCancellable> = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        theme.sink { [unowned self] _ in self.render() }
            .store(in: &cancellables)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)

        theme.sink { [unowned self] _ in self.render() }
            .store(in: &cancellables)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        // Draw background.
        self.backgroundColor.setFill()
        dirtyRect.fill()

        let bounds = self.bounds

        if let image = image, image.size.width * image.size.height > 0 {
            let aspect = image.size.width / image.size.height
            let fitSize = CGSize(width: min(bounds.width, aspect * bounds.height),
                                 height: min(bounds.height, bounds.width / aspect))
            image.draw(in: CGRect(origin: CGPoint(x: bounds.minX + (bounds.width - fitSize.width) / 2,
                                                  y: bounds.minY + (bounds.height - fitSize.height) / 2),
                                  size: fitSize))
        }
    }
    
    private func render() {
        self.image = render(at: theme.value.imageSize ?? self.bounds.size)
    }

    private func render(at size: CGSize) -> NSImage? {
        guard let chart = self.chart else { return nil }
        var options = BenchmarkRenderer.Options()
        let legendMargin = min(0.05 * size.width, 0.05 * size.height)
        options.showTitle = false
        options.legendPosition = chart.tasks.count > 10 ? .hidden : .topLeft
        options.legendHorizontalMargin = legendMargin
        options.legendVerticalMargin = legendMargin

        let renderer = BenchmarkRenderer(chart: chart,
                                         theme: self.theme.value,
                                         options: options,
                                         in: CGRect(origin: .zero, size: size))
        return renderer.image
    }
}
