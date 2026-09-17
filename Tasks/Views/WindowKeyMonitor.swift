import AppKit
import SwiftUI

/// Watches key presses in one window only, so other open documents are unaffected.
/// Used for keys the macOS field editor consumes before `.onKeyPress` sees them,
/// such as Backspace in an empty text field.
@MainActor
final class WindowKeyMonitor {
    fileprivate weak var view: NSView?
    private var token: Any?

    /// `handler` gets the key code and returns true when it used the key.
    func start(handler: @escaping @MainActor (UInt16) -> Bool) {
        start { keyCode, _ in handler(keyCode) }
    }

    /// Like `start(handler:)`, with the modifier keys held for that press.
    func start(handler: @escaping @MainActor (UInt16, NSEvent.ModifierFlags) -> Bool) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Only plain values cross into the main-actor block; NSEvent isn't Sendable.
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let windowNumber = event.windowNumber
            let used = MainActor.assumeIsolated {
                guard let window = self?.view?.window, Self.window(window, receives: windowNumber) else {
                    return false
                }
                return handler(keyCode, modifiers)
            }
            return used ? nil : event
        }
    }

    /// Key presses typed into a popover arrive tagged with the window it's attached to, because
    /// that window stays the app's key window. So a popover takes them while it has keyboard focus.
    private static func window(_ window: NSWindow, receives windowNumber: Int) -> Bool {
        if window.windowNumber == windowNumber {
            return true
        }
        return window.isKeyWindow && window.parent?.windowNumber == windowNumber
    }

    func stop() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
    }

    /// An invisible view that tells the monitor which window to watch.
    struct Anchor: NSViewRepresentable {
        let monitor: WindowKeyMonitor

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            monitor.view = view
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {}
    }
}
