# Tasks

A native macOS task manager that renders a plain `.json` file.

The file is the source of truth, the way Obsidian treats `.md` files. There is no database and no account. To sync or back up tasks, keep the file somewhere that already does that: iCloud Drive, Dropbox, or a git repo.

Built with Swift and SwiftUI only. It has zero third-party dependencies.

## Features

- Open any `.json` task list: File ▸ Open, Open Recent, or Finder ▸ Open With ▸ Tasks
- Sidebar filters: All, Today (including overdue), Upcoming, Completed
- Calendar with Month and Week views, similar to Calendar.app:
  - Drag a task to another day to reschedule it.
  - Double-click a day to add a task due that day.
  - Show a "No Due Date" tray. Drag tasks from it onto a day, or drop a task on it to clear the due date.
- Search across titles and notes
- Inspector for editing the title, notes and due date
- Autosave, undo/redo and File ▸ Revert To, all provided by the macOS document system

| Shortcut | Action |
|---|---|
| ⌘N | New task file |
| ⇧⌘N | New task |
| Space | Toggle done on the selected tasks |
| ⌫ | Delete the selected tasks |
| ⌘← / ⌘→ | Previous / next month or week (Calendar) |
| ⌘T | Go to today (Calendar) |
| ⌘1 / ⌘2 | Month / Week view (Calendar) |

## File format

```json
{
  "version": 1,
  "tasks": [
    {
      "id": "0B7E6C2A-7D0F-4C8E-9B61-2F6A1E3C4D01",
      "title": "Finish ML assignment",
      "notes": "",
      "done": false,
      "due": "2026-09-22",
      "createdAt": "2026-09-15T09:00:00Z"
    }
  ]
}
```

| Field | Type | Default if missing |
|---|---|---|
| `id` | UUID string | generated |
| `title` | string | `""` |
| `notes` | string | `""` |
| `done` | bool | `false` |
| `due` | `yyyy-MM-dd`, a local day | none |
| `createdAt` | ISO-8601 timestamp | time of loading |

The file is meant to be edited by hand as well as by the app. `{"tasks": [{"title": "Buy milk"}]}` is a valid file.

The app writes JSON pretty-printed with sorted keys, so git diffs stay small.

When you edit a file in the app and save it, a few things are not kept:
- Unknown fields.
- Due dates that can't be parsed.

See [`Samples/tasks.json`](Samples/tasks.json) for an example.

## Architecture

```
Tasks/
  TasksApp.swift              DocumentGroup scene
  Document/TaskDocument.swift FileDocument: reads and writes JSON
  Model/                      TaskFile, TaskItem (tolerant Codable), TaskFilter (filter + sort),
                              CalendarGrid (month/week date math)
  Views/                      ContentView (split view + inspector), TaskRow, TaskInspector
  Views/Calendar/             CalendarView, MonthGridView, WeekView, TaskChip, UndatedTray
TasksTests/                   Swift Testing: coding round-trips, filters, sorting, calendar grid
```

All edits go through the document binding. That binding records undo and marks the file dirty, so there is no separate state store.

## Build

Requires Xcode 26 or later and macOS 26 or later.

```sh
open Tasks.xcodeproj          # then ⌘R
xcodebuild test -scheme Tasks -destination 'platform=macOS'
```
