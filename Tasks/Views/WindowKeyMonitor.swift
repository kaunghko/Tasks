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
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Only plain values cross into the main-actor block; NSEvent isn't Sendable.
            let keyCode = event.keyCode
            let windowNumber = event.windowNumber
            let used = MainActor.assumeIsolated {
                guard let window = self?.view?.window, window.windowNumber == windowNumber else {
                    return false
                }
                return handler(keyCode)
            }
            return used ? nil : event
        }
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
