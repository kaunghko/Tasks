import AppKit
import SwiftUI

/// A compact, draggable task used in calendar cells and the undated tray.
struct TaskChip: View {
    @Binding var task: TaskItem
    let isSelected: Bool
    let actions: CalendarActions

    static let height: CGFloat = 18

    var body: some View {
        HStack(spacing: 4) {
            Toggle(isOn: $task.done) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .controlSize(.mini)
            Text(task.title.isEmpty ? "Untitled" : task.title)
                .lineLimit(1)
                .strikethrough(task.done)
                .foregroundStyle(foreground)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 4)
        .frame(height: Self.height)
        .background(background, in: .rect(cornerRadius: 4))
        .contentShape(.rect)
        .onTapGesture {
            actions.select(task.id, NSEvent.modifierFlags.contains(.command))
        }
        .draggable(task.id.uuidString)
        .contextMenu {
            Button(task.done ? "Mark as Not Done" : "Mark as Done") {
                actions.toggleDone([task.id])
            }
            Divider()
            Button("Delete", role: .destructive) {
                actions.delete([task.id])
            }
        }
        .help(task.title)
    }

    private var foreground: Color {
        if isSelected { return .white }
        if task.done { return .secondary }
        return task.isOverdue() ? .red : .primary
    }

    private var background: Color {
        if isSelected { return .accentColor }
        if task.done { return .secondary.opacity(0.1) }
        return task.isOverdue() ? .red.opacity(0.15) : .accentColor.opacity(0.15)
    }
}
