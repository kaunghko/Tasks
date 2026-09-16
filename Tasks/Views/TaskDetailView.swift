import SwiftUI

/// Title, kind, schedule and notes for one task or event, shown in a popover next to it.
struct TaskDetailView: View {
    @Binding var task: TaskItem
    @Environment(\.willSwitchKind) private var willSwitchKind

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
