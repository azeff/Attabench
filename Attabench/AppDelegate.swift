// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if sender.windows.isEmpty {
            sender.sendAction(#selector(NSDocumentController.openDocument(_:)), to: nil, from: sender)
        }
        return false
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // But automatic app termination may do it anyway. That's fine.
        return false
    }
}

