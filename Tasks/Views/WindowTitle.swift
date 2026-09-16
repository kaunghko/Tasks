import AppKit
import SwiftUI

/// Pins the window title to `title`, e.g. the current view ("Today", "Calendar").
/// `DocumentGroup` titles windows with the file name and resets it on save or rename,
/// and `.navigationTitle` doesn't override that, so this reapplies it whenever AppKit changes it.
struct WindowTitle: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> TitleView {
        TitleView()
    }

    func updateNSView(_ nsView: TitleView, context: Context) {
        nsView.title = title
    }

    final class TitleView: NSView {
        var title = "" {
            didSet { apply() }
        }
        private var observation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = window?.observe(\.title) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.apply() }
            }
            apply()
        }

        private func apply() {
            guard let window, !title.isEmpty, window.title != title else { return }
            window.title = title
        }
    }
}
