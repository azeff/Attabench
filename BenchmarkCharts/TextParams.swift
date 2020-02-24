// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa

extension BenchmarkTheme {
    public struct TextParams {
        public var font: NSFont
        public var color: NSColor

        public var attributes: [NSAttributedString.Key: Any] {
            [.foregroundColor: color,
             .font: font]
        }

        public var fontName: String {
            get {
                font.fontName
            }
            set {
                guard let font = NSFont(name: newValue, size: font.pointSize) else {
                    preconditionFailure("Font '\(newValue)' not found")
                }
                self.font = font
            }
        }
    }
}
