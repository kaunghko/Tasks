import AppKit

/// Finds where the caret goes for a click on laid-out text, so a list row can start editing
/// at the clicked character instead of selecting the whole title.
enum TextHitTest {
    /// The UTF-16 offset (what `NSTextView.setSelectedRange` takes) of the caret position nearest
    /// `point`, for `text` drawn in `font` and wrapped at `width`. `point` is relative to the text's top left.
    static func caretOffset(in text: String, font: NSFont, width: CGFloat, at point: CGPoint) -> Int {
        let length = (text as NSString).length
        guard length > 0 else { return 0 }

        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)

        // Below the last line: the end of the text.
        if point.y > layout.usedRect(for: container).maxY {
            return length
        }

        var fraction: CGFloat = 0
        var index = layout.characterIndex(for: point, in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
        if fraction > 0.5 {
            index += 1
        }
        index = min(max(index, 0), length)
        guard index < length else { return length }
        // Stay on a character boundary, e.g. not inside an emoji: past its middle, after it.
        let character = (text as NSString).rangeOfComposedCharacterSequence(at: index)
        guard character.location != index else { return index }
        return fraction > 0.5 ? character.upperBound : character.location
    }
}
