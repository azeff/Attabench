// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation

class RateLimiter: NSObject {
    
    var maxDelay: TimeInterval {
        didSet { now() }
    }
    
    private let action: () -> Void
    private var scheduled = false
    private var async = false
    private var performing = false
    private var next = Date.distantPast

    init(maxDelay: TimeInterval, async: Bool = false, action: @escaping () -> Void) {
        self.maxDelay = maxDelay
        self.async = async
        self.action = action
    }

    @objc func now() {
        guard !performing else { return }
        
        cancel()
        if async {
            performing = true
            DispatchQueue.main.async {
                self.performAction()
                self.performing = false
            }
        } else {
            performAction()
        }
    }

    private func performAction() {
        action()
        next = Date(timeIntervalSinceNow: self.maxDelay)
    }

    func later() {
        if scheduled { return }
        if performing { return }
        let now = Date()
        if next < now {
            self.now()
        } else {
            self.perform(#selector(RateLimiter.now), with: nil, afterDelay: next.timeIntervalSince(now))
            scheduled = true
        }
    }

    func nowIfNeeded() {
        if scheduled { now() }
    }

    private func cancel() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(RateLimiter.now), object: nil)
        scheduled = false
    }
}
