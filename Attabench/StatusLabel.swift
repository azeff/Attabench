// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa

class StatusLabel: NSTextField {
    
    private var status: String = ""
    
    private lazy var refreshStatus = RateLimiter(maxDelay: 0.1) { [unowned self] in
        self.stringValue = self.status
    }

    var refreshRate: TimeInterval {
        get { refreshStatus.maxDelay }
        set { refreshStatus.maxDelay = newValue }
    }

    // Rate-limited status setter. Helpful if you need to update status frequently without consuming too much CPU.
    var lazyStatus: String {
        get {
            status
        }
        set {
            status = newValue
            refreshStatus.later()
        }
    }

    // Update status text immediately.
    var immediateStatus: String {
        get {
            status
        }
        set {
            status = newValue
            refreshStatus.now()
        }
    }
}

