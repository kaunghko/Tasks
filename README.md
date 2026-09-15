# Tasks

A native macOS task manager that renders a plain `.json` file.

The file is the source of truth, the way Obsidian treats `.md` files. There is no database and no account. To sync or back up tasks, keep the file somewhere that already does that: iCloud Drive, Dropbox, or a git repo.

Built with Swift and SwiftUI. Its only dependency is [Sparkle](https://sparkle-project.org), which handles in-app updates.

## Features

- Open any `.json` task list: File ▸ Open, Open Recent, or Finder ▸ Open With ▸ Tasks
- Sidebar filters: All, Today (including overdue), Upcoming, Completed
- Calendar with Month and Week views, similar to Calendar.app:
  - Drag a task to another day to reschedule it.
  - Double-click a day to add a task due that day.
  - Show a "No Due Date" tray. Drag tasks from it onto a day, or drop a task on it to clear the due date.
- ⌘K search palette that jumps to tasks and views:
  - Typing searches task titles, task notes and views together.
  - Tab limits the search to tasks.
  - A leading `@` limits the search to views: `@today` (or `@daily`), `@upcoming`, `@done`, `@calendar`, `@month`, `@week`.
  - To search everything again, press Backspace in an empty field, press Tab again, or click ✕ on the scope token. Esc also removes a scope before it closes the palette.
- Click a task to edit its title, notes and due date in a popover
- Subtasks: in a task's notes, start a line with `- [ ] ` (or `- [x] `) to turn it into a checkbox. Other lines stay plain notes.
  - Return adds the next subtask. Return or Backspace on an empty subtask deletes it and ends the list.
  - To delete any subtask, click the ✕ that shows when you hover over it or edit it, or right-click it.
  - Task rows show progress, such as `1/2`, and search also matches subtask titles.
- Autosave, undo/redo and File ▸ Revert To, all provided by the macOS document system

| Shortcut | Action |
|---|---|
| ⌘N | New task file |
| ⇧⌘N | New task |
| ⌘K | Search palette |
| Tab / @ | Search tasks / views (in the palette) |
| ↑ ↓ ↩ Esc | Move, open, close (in the palette) |
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
      "notes": "Chapter 3 exercises",
      "subtasks": [
        { "id": "7A1D3F20-5B6C-4E8A-9D12-3C4B5A6F7E01", "title": "Q1 regression", "done": true },
        { "title": "Q2 logistic" }
      ],
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
| `subtasks` | array of `{id, title, done}`, where only `title` is needed | `[]`, and left out when empty |
| `done` | bool | `false` |
| `due` | `yyyy-MM-dd`, a local day | none |
| `createdAt` | ISO-8601 timestamp | time of loading |

The file is meant to be edited by hand as well as by the app. `{"tasks": [{"title": "Buy milk"}]}` is a valid file.

The app writes JSON pretty-printed with sorted keys, so git diffs stay small.

When you edit a file in the app and save it, a few things are not kept:
- Unknown fields.
- Due dates that can't be parsed.

## Architecture

```
Tasks/
  TasksApp.swift              DocumentGroup scene
  Document/TaskDocument.swift FileDocument: reads and writes JSON
  Model/                      TaskFile, TaskItem (tolerant Codable), Subtask + Checklist (`- [ ]` parsing),
                              TaskFilter (filter + sort),
                              CalendarGrid (month/week date math),
                              SearchPalette (query parsing + result ranking)
  Views/                      ContentView (split view), TaskRow, TaskDetailView (popover),
                              NotesEditor (subtask checklist + notes), WindowKeyMonitor
  Views/Calendar/             CalendarView, MonthGridView, WeekView, TaskChip, UndatedTray
  Views/Search/               SearchPaletteView (⌘K palette)
  Updates/                    CheckForUpdatesView (Sparkle menu item)
  AppIcon.icon                Icon Composer app icon
scripts/                      release.sh (sign, notarize, publish), ExportOptions.plist
TasksTests/                   Swift Testing: coding round-trips, filters, sorting, calendar grid,
                              palette search
```

All edits go through the document binding. That binding records undo and marks the file dirty, so there is no separate state store.

## Build

Requires Xcode 26 or later and macOS 26 or later.

```sh
open Tasks.xcodeproj          # then ⌘R
xcodebuild test -scheme Tasks -destination 'platform=macOS'
```

## Install

Download `Tasks-x.y.z.zip` from [Releases](https://github.com/kaunghko/Tasks/releases), unzip it, and drag `Tasks.app` into `/Applications`. Builds are signed with Developer ID and notarized by Apple, so they open without warnings. After that, the app checks for updates once a day and can install them itself. You can also use Tasks ▸ Check for Updates….

Maintainers: see [RELEASING.md](RELEASING.md).
