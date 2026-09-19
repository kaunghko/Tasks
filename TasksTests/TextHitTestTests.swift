import AppKit
import Testing
@testable import Tasks

@MainActor
struct TextHitTestTests {
    private let font = NSFont.systemFont(ofSize: 13)

    /// Where the caret at `offset` is drawn, measured the same way as the hit test.
    private func x(of prefix: String) -> CGFloat {
        (prefix as NSString).size(withAttributes: [.font: font]).width
    }

    @Test func emptyTextIsZero() {
        #expect(TextHitTest.caretOffset(in: "", font: font, width: 200, at: CGPoint(x: 50, y: 5)) == 0)
    }

    @Test func leftOfTextIsStart() {
        #expect(TextHitTest.caretOffset(in: "Buy milk", font: font, width: 200, at: CGPoint(x: -4, y: 5)) == 0)
    }

    @Test func pastTheEndIsLength() {
        #expect(TextHitTest.caretOffset(in: "Buy milk", font: font, width: 400, at: CGPoint(x: 300, y: 5)) == 8)
    }

    @Test func belowTheTextIsLength() {
        #expect(TextHitTest.caretOffset(in: "Buy milk", font: font, width: 400, at: CGPoint(x: 5, y: 80)) == 8)
    }

    @Test(arguments: [1, 4, 6])
    func clickNearACaretPositionLandsThere(offset: Int) {
        let text = "Buy milk"
        let prefix = String(text.prefix(offset))
        // Just right of the boundary rounds back to it; just left rounds forward to it.
        #expect(TextHitTest.caretOffset(in: text, font: font, width: 400, at: CGPoint(x: x(of: prefix) + 1, y: 5)) == offset)
        #expect(TextHitTest.caretOffset(in: text, font: font, width: 400, at: CGPoint(x: x(of: prefix) - 1, y: 5)) == offset)
    }

    @Test func secondLineOfWrappedText() {
        let text = "alpha beta gamma delta"
        let width = x(of: "alpha beta ") + 2
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        let offset = TextHitTest.caretOffset(in: text, font: font, width: width, at: CGPoint(x: 1, y: lineHeight * 1.5))
        #expect(offset == 11)
    }

    @Test func staysOnCharacterBoundaries() {
        let text = "👍🏽 done"
        let emoji = x(of: "👍🏽")
        for step in stride(from: 0, through: emoji, by: 1) {
            let offset = TextHitTest.caretOffset(in: text, font: font, width: 400, at: CGPoint(x: step, y: 5))
            #expect(offset == 0 || offset == ("👍🏽" as NSString).length)
        }
    }
}
