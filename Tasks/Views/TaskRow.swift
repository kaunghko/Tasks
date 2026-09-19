import AppKit
import SwiftUI

/// Where editing starts when a row expands: the character that was clicked, as a UTF-16 offset.
enum CaretTarget: Equatable {
    case title(Int)
    case notes(Int)
    /// The whole title selected, so typing replaces it, as for a new task.
    case selectedTitle
}

struct TaskRow: View {
    @Binding var task: TaskItem
    /// The occurrence to show the schedule of, when the event repeats.
    var occurrence: TaskItem?
    /// Expanded, the row edits the task in place: title, notes, subtasks and schedule.
    var isExpanded = false
    /// Where the caret goes when the row expands.
    var caret: CaretTarget = .selectedTitle
    /// Called on a plain click anywhere but the checkbox, with where the click landed in the text.
    var onOpen: (CaretTarget) -> Void = { _ in }
    /// Called on Esc (true) or a click outside the row (false) while it's expanded.
    var onClose: (_ byKeyboard: Bool) -> Void = { _ in }

    @State private var titleFrame: CGRect = .zero
    @State private var notesFrame: CGRect = .zero
    /// Detected phrases the user dismissed while the row is expanded.
    @State private var dismissedPhrases: Set<String> = []
    @State private var keyMonitor = WindowKeyMonitor()
    @FocusState private var isTitleFocused: Bool

    private static let headerSpace = "TaskRowHeader"

    var body: some View {
        let shown = occurrence ?? task
        let isFinished = shown.isFinished()

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if task.isEvent {
                    EventBar()
                        .frame(height: 14)
                        // Checkbox width, so event and task titles line up.
                        .frame(width: 16)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                } else {
                    Toggle(isOn: $task.done) { EmptyView() }
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                }
            }
            // Pinned beside the title: animated, it slides while the title swaps to a field.
            .transaction { $0.animation = nil }

            VStack(alignment: .leading, spacing: 8) {
                header(shown: shown, isFinished: isFinished)
                if isExpanded {
                    details
                        .padding(.bottom, 6)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isExpanded)
        }
        .padding(.vertical, 2)
        .opacity(shown.isEvent && isFinished && !isExpanded ? 0.6 : 1)
        .background(WindowKeyMonitor.Anchor(monitor: keyMonitor))
        .background(ExpandedRowMonitor(isExpanded: isExpanded, onClickOutside: { onClose(false) }))
        .task(id: isExpanded) {
            guard isExpanded else {
                keyMonitor.stop()
                dismissedPhrases = []
                return
            }
            keyMonitor.start(handler: handleKey(_:modifiers:))
            switch caret {
            case .title(let offset):
                await Caret.place(at: offset) { isTitleFocused = true }
            case .selectedTitle:
                await Caret.place(at: nil) { isTitleFocused = true }
            case .notes:
                // `NotesEditor` focuses itself from `initialCaret`.
                break
            }
        }
        .onDisappear { keyMonitor.stop() }
    }

    // Clicks here open the details. Not on the checkbox: checking a task off shouldn't
    // expand it, least of all a repeating one that stays in the list.
    private func header(shown: TaskItem, isFinished: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                // The title swaps between text and field instantly: a cross-fade makes it blink.
                if isExpanded {
                    TextField("Title", text: $task.title, prompt: Text("Untitled"), axis: .vertical)
                        .textFieldStyle(.plain)
                        .focused($isTitleFocused)
                        .transition(.identity)
                } else {
                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .strikethrough(task.done)
                        .foregroundStyle(isFinished ? .secondary : .primary)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.headerSpace)) } action: {
                            titleFrame = $0
                        }
                        .transition(.identity)
                    if !task.notes.isEmpty {
                        Text(task.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.headerSpace)) } action: {
                                notesFrame = $0
                            }
                            .transition(.identity)
                    }
                }
            }

            Spacer()

            if let progress = task.subtaskProgress {
                // Not a `Label`: the List aligns row separators to a Label's title,
                // which cut the separator short under rows with subtasks.
                HStack(spacing: 3) {
                    Image(systemName: "checklist")
                    Text("\(progress.done)/\(progress.total)")
                }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("\(progress.done) of \(progress.total) subtasks done")
            }

            if let recurrence = task.recurrence {
                Image(systemName: "repeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(recurrence.summary)
            }

            if let scheduleLabel = shown.scheduleLabel {
                Text(scheduleLabel)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(shown.isOverdue() ? .red : .secondary)
            }
        }
        .contentShape(.rect)
        .coordinateSpace(.named(Self.headerSpace))
        // Simultaneous, so the List still handles selection and ⌘/⇧-clicks.
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named(Self.headerSpace)).onEnded { tap in
            guard !isExpanded, !NSEvent.modifierFlags.contains(.command), !NSEvent.modifierFlags.contains(.shift)
            else { return }
            onOpen(caretTarget(at: tap.location))
        })
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let detected = task.detectedSchedule(ignoring: dismissedPhrases) {
                DetectedScheduleRow(
                    detected: detected,
                    preview: task.applying(detected),
                    onApply: { task = task.applying(detected) },
                    onDismiss: { dismissedPhrases.insert(detected.phrase) }
                )
                .font(.callout)
            }

            NotesEditor(task: $task, isInline: true, initialCaret: notesCaret)

            Form {
                TaskKindPicker(task: $task)
                    .pickerStyle(.segmented)
                    .fixedSize()
                TaskScheduleFields(task: $task)
                TaskRepeatFields(task: $task)
                LabeledContent(
                    "Created",
                    value: task.createdAt.formatted(date: .abbreviated, time: .shortened)
                )
                .foregroundStyle(.secondary)
            }
            .formStyle(.columns)
            .controlSize(.small)
            .padding(.top, 4)
        }
    }

    private var notesCaret: Int? {
        if case .notes(let offset) = caret { offset } else { nil }
    }

    /// The character under a click on the title or the notes line; elsewhere, the end of the title.
    private func caretTarget(at point: CGPoint) -> CaretTarget {
        let body = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let caption = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        if !task.notes.isEmpty, notesFrame.insetBy(dx: 0, dy: -1).contains(point) {
            // The line shows only the start of the notes, so wrapping doesn't come into it.
            let firstLine = task.notes.prefix { !$0.isNewline }
            let offset = TextHitTest.caretOffset(
                in: String(firstLine), font: caption, width: .greatestFiniteMagnitude,
                at: CGPoint(x: point.x - notesFrame.minX, y: 1))
            return .notes(offset)
        }
        guard !task.title.isEmpty, point.x < titleFrame.maxX + 8 else {
            return .title((task.title as NSString).length)
        }
        let offset = TextHitTest.caretOffset(
            in: task.title, font: body, width: titleFrame.width,
            at: CGPoint(x: point.x - titleFrame.minX, y: min(max(point.y - titleFrame.minY, 0), titleFrame.height - 1)))
        return .title(offset)
    }

    /// Tab in the title applies the suggestion, and Esc closes the row. The field editor takes
    /// Tab to move focus before `.onKeyPress` sees it, so this goes through the window's key monitor.
    private func handleKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard modifiers.intersection([.shift, .command, .option, .control]).isEmpty else { return false }
        switch keyCode {
        case 48:
            guard isTitleFocused, let detected = task.detectedSchedule(ignoring: dismissedPhrases) else { return false }
            // One assignment, so it's a single undo step. The kind stays as it is.
            task = task.applying(detected)
            return true
        case 53:
            guard keyMonitor.isFocusInRow else { return false }
            onClose(true)
            return true
        default:
            return false
        }
    }
}

/// Watches the List row it sits in while expanded: a click elsewhere in the window closes it.
/// The row stays selected, because the table only lets a click into a text field in a selected row,
/// but it draws no highlight, its content keeps normal colors instead of the highlight's white,
/// and its text fields lose the opaque background the table gives field editors.
private struct ExpandedRowMonitor: NSViewRepresentable {
    let isExpanded: Bool
    let onClickOutside: () -> Void

    func makeNSView(context: Context) -> ExpandedRowMonitorView { ExpandedRowMonitorView() }

    func updateNSView(_ view: ExpandedRowMonitorView, context: Context) {
        view.onClickOutside = onClickOutside
        view.isExpanded = isExpanded
    }
}

private final class ExpandedRowMonitorView: NSView {
    var onClickOutside: () -> Void = {}
    var isExpanded = false {
        didSet {
            guard isExpanded != oldValue else { return }
            isExpanded ? start() : stop()
        }
    }
    private var focusObservation: NSKeyValueObservation?
    private var styleObservation: NSKeyValueObservation?
    private var clickMonitor: Any?
    private var isClickingOutside = false

    private var rowView: NSView? {
        var current = superview
        while let candidate = current, !(candidate is NSTableRowView) {
            current = candidate.superview
        }
        return current
    }

    private var cellView: NSTableCellView? {
        var current = superview
        while let candidate = current, !(candidate is NSTableCellView) {
            current = candidate.superview
        }
        return current as? NSTableCellView
    }

    private func start() {
        guard let window else { return }
        (rowView as? NSTableRowView)?.selectionHighlightStyle = .none
        // The table sets the style whenever selection or focus changes; put it back each time, right
        // away. Even one frame late, the row draws its text in the highlight's white on no highlight.
        cellView?.backgroundStyle = .normal
        styleObservation = cellView?.observe(\.backgroundStyle, options: [.new]) { cell, _ in
            MainActor.assumeIsolated {
                if cell.backgroundStyle != .normal {
                    cell.backgroundStyle = .normal
                }
            }
        }
        focusObservation = window.observe(\.firstResponder, options: [.initial, .new]) { [weak self] _, _ in
            // Focus is still moving when this fires; style the new editor once it's in place.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.clearEditorBackground() } }
        }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            let windowNumber = event.windowNumber
            let location = event.locationInWindow
            let isDown = event.type == .leftMouseDown
            MainActor.assumeIsolated {
                // Clicks in other windows, like a date picker's calendar, leave the row open.
                guard let self, let window = self.window, window.windowNumber == windowNumber,
                      let row = self.rowView
                else { return }
                if isDown {
                    self.isClickingOutside = !row.bounds.contains(row.convert(location, from: nil))
                } else if self.isClickingOutside {
                    self.isClickingOutside = false
                    // Once the click is handled, so a click on another task opens it straight from this
                    // one, without a frame where neither is open.
                    DispatchQueue.main.async { MainActor.assumeIsolated { self.onClickOutside() } }
                }
            }
            return event
        }
    }

    private func stop() {
        focusObservation = nil
        styleObservation = nil
        (rowView as? NSTableRowView)?.selectionHighlightStyle = .regular
        if let row = rowView as? NSTableRowView {
            cellView?.backgroundStyle = row.interiorBackgroundStyle
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        clickMonitor = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stop()
        } else if isExpanded, clickMonitor == nil {
            start()
        }
    }

    private func clearEditorBackground() {
        guard let row = rowView, let editor = window?.firstResponder as? NSTextView,
              editor.isFieldEditor, editor.isDescendant(of: row)
        else { return }
        editor.drawsBackground = false
    }
}

/// The colored bar that stands in for a checkbox on events.
struct EventBar: View {
    var color: Color = .accentColor

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: 3)
    }
}
