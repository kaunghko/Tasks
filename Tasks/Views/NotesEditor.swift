import AppKit
import SwiftUI

/// A task's subtasks and notes. Typing `- [ ] ` at the start of a notes line turns that line
/// into a subtask; Return adds the next one, and Return or Backspace on an empty one ends the list.
struct NotesEditor: View {
    @Binding var task: TaskItem

    @FocusState private var focus: NotesField?
    @State private var keyMonitor = WindowKeyMonitor()

    var body: some View {
        Section("Notes") {
            ForEach(task.subtasks) { subtask in
                SubtaskRow(
                    subtask: $task.subtasks[id: subtask.id],
                    focus: $focus,
                    onSubmit: { submit(subtask.id) },
                    onDelete: { remove(subtask.id) }
                )
            }

            TextEditor(text: $task.notes)
                .font(.body)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .focused($focus, equals: .notes)
                .background(WindowKeyMonitor.Anchor(monitor: keyMonitor))
                .onAppear { keyMonitor.start(handler: handleKey) }
                .onDisappear { keyMonitor.stop() }
                .onChange(of: task.notes) { _, notes in
                    moveChecklistLines(from: notes)
                }
        }
    }

    /// Return on a subtask adds another below it; on an empty one it ends the list.
    private func submit(_ id: Subtask.ID) {
        guard let index = task.subtasks.firstIndex(where: { $0.id == id }) else { return }
        if task.subtasks[index].title.isEmpty {
            task.subtasks.remove(at: index)
            focus = .notes
        } else {
            let next = Subtask()
            task.subtasks.insert(next, at: index + 1)
            // The new row has to exist before it can take focus.
            Task { focus = .subtask(next.id) }
        }
    }

    /// Deletes a subtask. If it was being edited, focus moves to the one above, or to the notes.
    private func remove(_ id: Subtask.ID) {
        guard let index = task.subtasks.firstIndex(where: { $0.id == id }) else { return }
        task.subtasks.remove(at: index)
        if focus == .subtask(id) {
            focus = index > 0 ? .subtask(task.subtasks[index - 1].id) : .notes
        }
    }

    /// Backspace in an empty subtask deletes it. The field editor swallows Backspace in an
    /// empty field before `.onKeyPress` sees it, so this runs from the window's key monitor.
    private func handleKey(_ keyCode: UInt16) -> Bool {
        guard keyCode == 51, case .subtask(let id)? = focus,
              task.subtasks.first(where: { $0.id == id })?.title.isEmpty == true
        else { return false }
        remove(id)
        return true
    }

    private func moveChecklistLines(from notes: String) {
        let checklist = Checklist.extract(from: notes, whileTyping: true)
        guard let last = checklist.subtasks.last else { return }
        // One assignment, so the conversion is a single undo step.
        var updated = task
        updated.notes = checklist.notes
        updated.subtasks += checklist.subtasks
        task = updated
        Task { focus = .subtask(last.id) }
    }
}

private enum NotesField: Hashable {
    case subtask(Subtask.ID)
    case notes
}

/// A checkbox, an editable title, and a delete button that shows on hover or while editing.
private struct SubtaskRow: View {
    @Binding var subtask: Subtask
    var focus: FocusState<NotesField?>.Binding
    let onSubmit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        let showsDelete = isHovered || focus.wrappedValue == .subtask(subtask.id)
        HStack(spacing: 6) {
            Toggle(isOn: $subtask.done) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
            TextField("Subtask", text: $subtask.title, prompt: Text("Subtask"))
                .textFieldStyle(.plain)
                .labelsHidden()
                .strikethrough(subtask.done)
                .foregroundStyle(subtask.done ? .secondary : .primary)
                .focused(focus, equals: .subtask(subtask.id))
                .onSubmit(onSubmit)
            Button("Delete Subtask", systemImage: "xmark.circle.fill", action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Delete Subtask")
                .opacity(showsDelete ? 1 : 0)
                .allowsHitTesting(showsDelete)
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Delete Subtask", role: .destructive, action: onDelete)
        }
    }
}
