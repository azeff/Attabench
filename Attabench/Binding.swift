//
//  Binding.swift
//  Attabench
//
//  Created by Evgeny Kazakov on 2/24/20.
//  Copyright © 2020 Károly Lőrentey. All rights reserved.
//

import AppKit
import Combine
import BenchmarkModel

// MARK: - Control binding

class Binding<Control: NSControl, Value> {

    static func bind<P: Publisher>(
        control: Control,
        toView: @escaping (Value, Control) -> Void,
        fromView: @escaping (Value) -> Void,
        controlValue: @escaping (Control) -> Value,
        in inputStream: P
    ) -> AnyCancellable where P.Output == Value, P.Failure == Never {
        let inCancellable = inputStream.sink { toView($0, control) }
        let outCancellable = ControlActionHandler(value: controlValue, handler: fromView).connect(control)
        
        return AnyCancellable {
            inCancellable.cancel()
            outCancellable.cancel()
        }
    }

    static func bind<P: Publisher>(
        control: Control,
        toView: @escaping (Value, Control) -> Void,
        fromView: @escaping (Value) -> Void,
        controlValue: @escaping (Control) -> Value?,
        in inputStream: P
    ) -> AnyCancellable where P.Output == Value, P.Failure == Never {
        let inCancellable = inputStream.sink { toView($0, control) }
        let outCancellable = ControlActionHandler(
            value: controlValue,
            handler: { value in
                guard let value = value else { return }
                fromView(value)
            }
        ).connect(control)
        
        return AnyCancellable {
            inCancellable.cancel()
            outCancellable.cancel()
        }
    }
}

extension Binding where Control == NSButton, Value == Bool {
    static func bind(
        _ button: NSButton,
        with subject: CurrentValueSubject<Value, Never>
    ) -> AnyCancellable {
        Binding.bind(
            control: button,
            toView: { $1.state = $0 ? .on : .off },
            fromView: { [unowned subject] in subject.value = $0 },
            controlValue: { $0.state == .on },
            in: subject
        )
    }
}

extension Binding where Control == NSTextField, Value == Time {
    static func bind(
        _ field: NSTextField,
        with subject: CurrentValueSubject<Time, Never>
    ) -> AnyCancellable {
        Binding.bind(
            control: field,
            toView: { $1.stringValue = String($0) },
            fromView: { [unowned subject] in
                subject.value = $0
            },
            controlValue: { Time($0.stringValue) },
            in: subject
        )
    }
}

class ControlActionHandler<Control: NSControl, Value> {
    
    private let value: (Control) -> Value
    private let handler: (Value) -> Void
    private weak var view: Control?
    
    init(value: @escaping (Control) -> Value, handler: @escaping (Value) -> Void) {
        self.value = value
        self.handler = handler
    }
    
    func connect(_ view: Control) -> AnyCancellable {
        self.view = view
        view.target = self
        view.action = #selector(onAction)
        
        return AnyCancellable {
            self.view?.target = nil
            self.view?.action = nil
        }
    }
    
    @objc
    private func onAction(_ sender: AnyObject) {
        guard let view = sender as? Control else {
            fatalError("Sender of wrong type")
        }
        
        handler(value(view))
    }
}

// MARK: - Menu binding

class MenuBinding<Value: Equatable> {
    
    typealias Item = (title: String, value: Value)
    
    static func bind<Stream: Publisher>(
        button: NSPopUpButton,
        stream: Stream,
        items: [Item],
        onSelect: @escaping (Value) -> Void
    ) -> AnyCancellable where Stream.Output == Value, Stream.Failure == Never {
        
        let actionHandler = MenuItemActionHandler(handler: onSelect)
        
        let menu = NSMenu()
        let menuItems = items.map { title, value -> NSMenuItem in
            let menuItem = NSMenuItem(title: title, action: #selector(MenuItemActionHandler<Value>.onAction), keyEquivalent: "")
            menuItem.target = actionHandler
            menuItem.representedObject = value
            return menuItem
        }
        menuItems.forEach(menu.addItem)
        button.menu = menu
        
       let inputCancellable = stream
            .sink { [unowned button] value in
                guard
                    let menu = button.menu,
                    let item = menu.items.first(where: { ($0.representedObject as? Value) == value })
                    else { return }
                
                if button.selectedItem != item {
                    button.select(item)
                }
            }
        
        let actionHandlerCancellable = CaptureReferenceCancellable(actionHandler)
        return AnyCancellable {
            inputCancellable.cancel()
            actionHandlerCancellable.cancel()
        }
    }
}

class MenuItemActionHandler<Value> {
    
    private let handler: (Value) -> Void
    
    init(handler: @escaping (Value) -> Void) {
        self.handler = handler
    }
    
    @objc
    func onAction(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Value else { return }
        handler(value)
    }
}

private class CaptureReferenceCancellable<T>: Cancellable {
    
    private var obj: T?
    
    init(_ obj: T) {
        self.obj = obj
    }
    
    func cancel() {
        obj = nil
    }
}
