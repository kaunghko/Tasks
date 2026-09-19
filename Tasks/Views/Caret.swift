import AppKit

/// Focuses a text field and puts the caret at one character. AppKit selects all of a field's text
/// when it gains focus, so a click that should land at one character has to put it back.
@MainActor
enum Caret {
    /// Calls `focus` (e.g. setting a `@FocusState`), then places the caret at `offset`, a UTF-16
    /// offset, in the text view that takes focus; nil selects all the text.
    static func place(at offset: Int?, focus: () -> Void) async {
        let previous = focusOwner().map(ObjectIdentifier.init)
        // Move the caret the moment the field takes focus, before it draws with everything selected.
        let observation = NSApp.keyWindow?.observe(\.firstResponder, options: [.new]) { _, _ in
            MainActor.assumeIsolated {
                guard let editor = focusedEditor(other: previous) else { return }
                select(offset, in: editor)
            }
        }
        // Moving between fields, AppKit selects everything after focus arrives; put the caret back.
        let selectionObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification, object: nil, queue: nil
        ) { note in
            let changed = (note.object as? NSTextView).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let editor = focusedEditor(other: previous), ObjectIdentifier(editor) == changed,
                      editor.selectedRange() != range(offset, in: editor)
                else { return }
                select(offset, in: editor)
            }
        }
        defer {
            observation?.invalidate()
            NotificationCenter.default.removeObserver(selectionObserver)
        }

        focus()
        // Focus moves on SwiftUI's next update. A field that's still appearing, such as one fading in,
        // can drop the request, so ask again until it takes focus.
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(16))
            if let editor = focusedEditor(other: previous) {
                select(offset, in: editor)
                return
            }
            focus()
        }
    }

    /// The text view with keyboard focus, if focus has moved away from `previous`.
    private static func focusedEditor(other previous: ObjectIdentifier?) -> NSTextView? {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
              focusOwner().map(ObjectIdentifier.init) != previous
        else { return nil }
        return editor
    }

    private static func select(_ offset: Int?, in editor: NSTextView) {
        editor.setSelectedRange(range(offset, in: editor))
    }

    private static func range(_ offset: Int?, in editor: NSTextView) -> NSRange {
        let length = (editor.string as NSString).length
        return offset.map { NSRange(location: min($0, length), length: 0) } ?? NSRange(location: 0, length: length)
    }

    /// What has focus: the text field a shared field editor is editing, or the responder itself.
    private static func focusOwner() -> AnyObject? {
        let responder = NSApp.keyWindow?.firstResponder
        if let editor = responder as? NSTextView, editor.isFieldEditor {
            return editor.delegate
        }
        return responder
    }
}
