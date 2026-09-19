# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

K2Tasks (the Xcode project, scheme, Swift module and bundle ID are still named `Tasks`) is a native macOS (26+) SwiftUI app that renders and edits a plain `.json` task file. The file is the source of truth: no database, no account. README.md documents user-facing features, shortcuts and the JSON format, so keep it in sync when behavior changes.

## Commands

Requires Xcode 26+. Swift 6 language mode.

```sh
xcodebuild build -scheme Tasks -destination 'platform=macOS'
xcodebuild test  -scheme Tasks -destination 'platform=macOS'
# One suite or one test (Swift Testing):
xcodebuild test -scheme Tasks -destination 'platform=macOS' -only-testing:TasksTests/SubtaskTests
xcodebuild test -scheme Tasks -destination 'platform=macOS' -only-testing:'TasksTests/SubtaskTests/extractKeepsNoteLinesInOrder()'
```

A single Swift Testing test needs the trailing `()`. Without it, xcodebuild runs zero tests and still reports `TEST SUCCEEDED`, so check for `Test run with N tests` in the output.

The Xcode project uses file-system synchronized groups, so new `.swift` files under `Tasks/` or `TasksTests/` are picked up without editing `project.pbxproj`.

Releases: `scripts/release.sh <x.y.z>` from a clean `main` (see RELEASING.md). It tests, bumps `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in the pbxproj, archives, notarizes, regenerates `appcast.xml`, tags, publishes the GitHub Release and pushes. Don't run it or hand-edit `appcast.xml` unless asked. Signing keys and the notarization password live in the Keychain, never in the repo.

## Architecture

- **State lives in the document.** `TasksApp` is a `DocumentGroup` over `TaskDocument` (a `FileDocument`). `ContentView` gets `@Binding var document`, and every mutation goes through `document.file.tasks`. That binding is what gives undo/redo, dirty tracking and autosave, so there is no separate store; don't introduce one. View-only state (selection, current destination, expanded row or open popover, palette visibility) is `@State` in `ContentView`, passed down as bindings and callbacks (e.g. `CalendarView`'s `onReschedule`, `onDelete`).
- **Bind to tasks by id, not index.** Use the `[id:]` subscripts on `[TaskItem]` and `[Subtask]` (`$document.file.tasks[id: task.id]`). Index-based `ForEach($array)` bindings crashed after deletions.
- **Tolerant, round-trip-stable JSON.** `TaskItem.init(from:)` defaults every missing field so hand-written files load. `TaskFile` encodes pretty-printed with sorted keys for small git diffs. `due` is a local day (`yyyy-MM-dd`, start of day); a task's optional `dueTime` (`TimeOfDay`) is written into `due` as a local-offset timestamp and cleared whenever `due` is nil, and `createdAt` is truncated to whole seconds so values round-trip. `subtasks` is omitted when empty so older files save unchanged. An entry with `start`/`end` (local-offset ISO timestamps) is an event. Events live in the same `tasks` array, never have `done`, keep `due` in sync with the start day in memory, and don't write `due`/`done`. On decode, `- [ ]`/`- [x]` lines in `notes` move into `subtasks` (`Checklist.extract`). An optional `repeat` (`Recurrence`) is omitted when nil. `alert` (`TaskAlert`: minutes before, or `"none"`) is omitted at the default, at the time. On a task, `done`'s `didSet` calls `rollForward`, so every checkbox moves a repeating task to its next due date instead of completing it. A repeating event stays one entry whose `start` is the first occurrence: `CalendarGrid.tasksByDay(_:in:)` expands it into per-occurrence copies with the same id, and `TaskFilter.apply` shows its `currentOccurrence`. Views take that copy as `occurrence` for times and dragging but bind edits to the stored item, and drops move the whole series (`moveSeries`). Any format change needs a matching test in `TaskCodingTests` and a README update.
- **Logic in SwiftUI-free models, tested; views stay thin.** `Model/` holds `TaskFilter` (sidebar filters + sort), `CalendarGrid` (locale-aware month/week date math), `EventLayout` (week hour-grid placement of overlapping events), `SearchPalette` (query parsing for Tab/`@` scopes + result ranking), `Recurrence` (repeat rules and occurrence math), `TextHitTest` (the character under a click, for putting the caret there), `ScheduleParser` (English dates, times, repeat rules and alerts typed into a title, applied by `TaskItem.apply` only when the user presses Tab or clicks Apply in the task details; applying never switches task/event; a time on a task becomes its `dueTime`) and `Checklist` (in `Subtask.swift`). Put new non-trivial logic there with Swift Testing tests (`@Test`, `#expect`, parameterized `arguments:`), not in views.
- **Keyboard handling quirks.** The macOS field editor swallows some keys (e.g. Backspace in an empty field) before SwiftUI's `onKeyPress` sees them. `WindowKeyMonitor` is a window-scoped `NSEvent` local monitor for those cases, used by the search palette and `NotesEditor`. Window-level shortcuts like Space-to-toggle must ignore presses while the first responder is an `NSText`, or they fire while typing in a task's details.
- **Calendar dragging uses SwiftUI gestures, not system drag and drop.** Chips and event blocks get `.calendarDragSource`, and places that accept drops get `.calendarDropZone`, which reports its frame in the shared `CalendarDragState.space` coordinate space. `CalendarDrop.target` (in `Model/`, tested) picks the target under the pointer, so the calendar can preview the landing spot live. A drop animates the document change with `withAnimation`.
- **Notifications** are local `UNUserNotificationCenter` requests, scheduled ahead so macOS delivers them with the app closed. `Reminders.reminders(for:)` (in `Model/`, tested) picks them: events and tasks with a `dueTime`, next 14 days, capped at 60. `ContentView` hands them to `NotificationScheduler` whenever the tasks change and hourly, under a per-document identifier prefix (file path, or a UUID while untitled) so documents don't remove each other's.
- **Task details.** `detailTaskID` in `ContentView` is the item being edited. In the list views, its `TaskRow` expands in place. The title `Text` becomes a `TextField` at the same spot, and the fields go below it. These are the same `TaskKindPicker` / `TaskScheduleFields` / `TaskRepeatFields` / `NotesEditor` the calendar's `TaskDetailView` popover uses, so a new field goes in both. The row's `SpatialTapGesture` turns the click point into a `CaretTarget` via `TextHitTest`, and `Caret.place` puts the caret there once the field has focus. AppKit selects all text on focus, so this has to happen after.
  - The expanded row stays selected, because `NSTableView` only lets a click into a text field in a selected row. `ExpandedRowMonitor` hides the row's highlight and resets the cell's `backgroundStyle`, because otherwise SwiftUI draws the content in the highlight's white. It also clears field editors' opaque background and closes the row on a click outside it.
  - `.selectionDisabled` and deselecting both break clicks into fields.
  - Don't expand or collapse a row inside `withAnimation`. `List` hands the animation to its table, which fades the whole row as if reloading it, and the title and checkbox blink. `TaskRow` fades in only its own fields.
  - `ExpandedRowMonitor` also has to reset the style synchronously. One frame late, the row draws white text on no highlight.
  - `Caret.place` sets the caret in KVO and selection-change callbacks, not after a delay, so the title never shows fully selected.
  - A click on another row opens it without collapsing this one first. The outside-click close waits for mouse-up and is skipped if another row has opened.
  - While a row is open, `frozenOrder` keeps the list order. It's cleared after the collapse animation, because re-sorting and resizing a row in the same update leaves `List` with stale row heights.
- **Updates.** Sparkle 2 is the only dependency (SwiftPM). The app is sandboxed, so `Tasks.entitlements` has mach-lookup exceptions for Sparkle's XPC installer services; the feed URL and EdDSA public key are in `Tasks-Info.plist`.

## Verifying UI changes

Unit tests don't cover view behavior, and `ImageRenderer` can't draw scroll views. Past UI bugs were reproduced by hosting a view in an offscreen `NSWindow`, sending real key events through `NSApp.sendEvent`, and snapshotting it to a bitmap, sometimes via a small standalone `swiftc` harness that compiles only the views involved. Popovers are a trap: while one has keyboard focus, `NSApp.keyWindow` stays the document window and key events carry its window number, so a harness that sends events straight to the popover window can pass while the real app fails. For popover keyboard behavior, drive the real `DocumentGroup` + `ContentView` in a harness app bundle (with `CFBundleDocumentTypes` in its Info.plist) and post events to `NSApp.keyWindow`.

## git practices
- After making any changes, ask me whether to commit or not. 
- If I say commit, start the comment with "Add: ..." for feature addition, "Fix: .." for any bug fixes, etc. 
- Never include "Co-authored by Claude", "Written by Claude", etc. at the end of the comment. And make them at most 2 lines max. Keep it concise and simple.
