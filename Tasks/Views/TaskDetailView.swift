import SwiftUI

/// Title, kind, schedule and notes for one task or event, shown in a popover next to it.
struct TaskDetailView: View {
    @Binding var task: TaskItem
    @Environment(\.willSwitchKind) private var willSwitchKind
    /// Detected phrases the user dismissed while this popover is open.
    @State private var dismissedPhrases: Set<String> = []
    @State private var keyMonitor = WindowKeyMonitor()
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        Form {
            Section {
                Picker("Kind", selection: kind) {
                    Text("Task").tag(false)
                    Text("Event").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                TextField("Title", text: $task.title, axis: .vertical)
                    .focused($isTitleFocused)
                if let detected {
                    DetectedScheduleRow(
                        detected: detected,
                        preview: applying(detected),
                        onApply: { apply(detected) },
                        onDismiss: { dismissedPhrases.insert(detected.phrase) }
                    )
                }
                if !task.isEvent {
                    Toggle("Completed", isOn: $task.done)
                }
            }

            Section {
                if task.start != nil, task.end != nil {
                    // No `in:` range on Ends: a range that moves with the start makes the picker
                    // clamp and write back mid-update. `eventEnd` keeps the end after the start.
                    DatePicker("Starts", selection: $task.eventStart, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $task.eventEnd, displayedComponents: [.date, .hourAndMinute])
                } else {
                    Toggle("Due Date", isOn: $task.hasDueDate)
                    if task.hasDueDate {
                        DatePicker("Date", selection: $task.dueDay, displayedComponents: .date)
                        Toggle("Time", isOn: $task.hasDueTime)
                        if task.hasDueTime {
                            DatePicker("Due At", selection: $task.dueTimeDate, displayedComponents: .hourAndMinute)
                        }
                    }
                }
            }

            Section {
                Picker("Repeat", selection: $task.repeatFrequency) {
                    Text("Never").tag(Recurrence.Frequency?.none)
                    ForEach(Recurrence.Frequency.allCases) { frequency in
                        Text(frequency.title).tag(Optional(frequency))
                    }
                }
                if let recurrence = task.recurrence {
                    Stepper(value: $task.repeatInterval, in: 1...99) {
                        Text("Every \(recurrence.interval) \(recurrence.frequency.unit(recurrence.interval))")
                    }
                    if recurrence.frequency == .weekly {
                        WeekdayPicker(selection: $task.repeatWeekdays)
                    }
                    Toggle("End Repeat", isOn: $task.hasRepeatEnd)
                    if recurrence.until != nil {
                        DatePicker("Until", selection: $task.repeatUntil, displayedComponents: .date)
                    }
                }
            }

            NotesEditor(task: $task)

            Section {
                LabeledContent(
                    "Created",
                    value: task.createdAt.formatted(date: .abbreviated, time: .shortened)
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 300, height: 460)
        .background(WindowKeyMonitor.Anchor(monitor: keyMonitor))
        .onAppear { keyMonitor.start(handler: handleKey(_:modifiers:)) }
        .onDisappear { keyMonitor.stop() }
    }

    /// What the title suggests, unless dismissed.
    private var detected: DetectedSchedule? {
        guard let detected = ScheduleParser.parse(task.title),
              !dismissedPhrases.contains(detected.phrase)
        else { return nil }
        return detected
    }

    /// Tab in the title field applies the suggestion. The field editor takes Tab to move focus
    /// before `.onKeyPress` sees it, so this goes through the window's key monitor.
    private func handleKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard keyCode == 48, isTitleFocused,
              modifiers.intersection([.shift, .command, .option, .control]).isEmpty,
              let detected
        else { return false }
        apply(detected)
        return true
    }

    private func applying(_ detected: DetectedSchedule) -> TaskItem {
        var item = task
        item.apply(detected)
        return item
    }

    /// One assignment, so it's a single undo step. The kind stays as it is.
    private func apply(_ detected: DetectedSchedule) {
        task = applying(detected)
    }

    /// Switches kinds in one assignment, so it's a single undo step. Switching back restores
    /// the event's times or the task's done state from before, even if the popover reopened in between.
    private var kind: Binding<Bool> {
        Binding(
            get: { task.isEvent },
            set: { toEvent in
                guard toEvent != task.isEvent else { return }
                var item = task
                var memory = KindSwitchMemory.shared[item.id] ?? KindSwitchMemory()
                if toEvent {
                    memory.done = item.done
                    item.makeEvent(previous: memory.eventTimes)
                } else {
                    if let start = item.start, let end = item.end {
                        memory.eventTimes = (start, end)
                    }
                    item.makeTask(done: memory.done)
                }
                KindSwitchMemory.shared[item.id] = memory
                willSwitchKind(item.id)
                task = item
            }
        )
    }
}

/// What was found in the title and what applying it would set, with Apply (Tab or ⌘↩) and dismiss buttons.
private struct DetectedScheduleRow: View {
    let detected: DetectedSchedule
    let preview: TaskItem
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("“\(detected.phrase)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Button("Apply", action: onApply)
                        .controlSize(.small)
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("Apply (Tab or ⌘↩)")
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Ignore")
                    .accessibilityLabel("Ignore")
                }
                if let schedule {
                    Text(schedule)
                }
                if let rule = preview.recurrence, detected.recurrence != nil {
                    Text(rule.summary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var symbol: String {
        if detected.start != nil { return "clock" }
        if detected.day != nil { return "calendar" }
        return "arrow.clockwise"
    }

    /// "Tomorrow · 15:00–16:00", or just the day.
    private var schedule: String? {
        let time = detected.start == nil ? nil : preview.timeRangeLabel ?? preview.dueTimeLabel
        let parts = [preview.dueLabel, time].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Seven round day toggles in the locale's week order. The last picked day can't be unpicked.
private struct WeekdayPicker: View {
    @Binding var selection: Set<Recurrence.Weekday>

    var body: some View {
        let calendar = Calendar.current
        let days = Recurrence.Weekday.allCases.sorted {
            $0.offset(firstWeekday: calendar.firstWeekday) < $1.offset(firstWeekday: calendar.firstWeekday)
        }

        HStack(spacing: 4) {
            ForEach(days) { day in
                let isOn = selection.contains(day)
                Button {
                    selection.formSymmetricDifference([day])
                } label: {
                    Text(calendar.veryShortWeekdaySymbols[day.rawValue - 1])
                        .font(.caption.weight(.medium))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(isOn ? Color.white : .primary)
                        .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.weekdaySymbols[day.rawValue - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// What an item had before it last switched kinds. Kept for the session only, never saved.
@MainActor
private struct KindSwitchMemory {
    static var shared: [TaskItem.ID: KindSwitchMemory] = [:]

    var done = false
    var eventTimes: (start: Date, end: Date)?
}

extension EnvironmentValues {
    /// Called just before an item switches between task and event, so whoever presents its
    /// popover can reopen it if the view it points at goes away.
    @Entry var willSwitchKind: @MainActor (TaskItem.ID) -> Void = { _ in }
}
