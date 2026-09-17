# K2Tasks

A native macOS task manager that renders a plain `.json` file.

The file is the source of truth, the way Obsidian treats `.md` files. There is no database and no account. To sync or back up tasks, keep the file somewhere that already does that: iCloud Drive, Dropbox, or a git repo.

Built with Swift and SwiftUI. Its only dependency is [Sparkle](https://sparkle-project.org), which handles in-app updates.

## Features

- Open any `.json` task list: File ▸ Open, Open Recent, or Finder ▸ Open With ▸ K2Tasks
- Sidebar filters (hidden by default; show it with the toolbar button): All, Today (including overdue), Upcoming, Completed
- Events with start and end times, next to tasks:
  - Add one with ⌥⌘N, drag from the start to the end time on the Week view's hour grid, double-click the grid for a one-hour event, or switch a task to Event in its popover. Switching back and forth keeps the event's times and the task's done state.
  - Events show a colored bar instead of a checkbox, and their time range, such as `09:00–10:15`.
  - Today lists events that haven't ended yet. Events fade once they're over and never count as completed.
- Calendar with Month and Week views, similar to Calendar.app:
  - The Week view is an hourly grid. Events are blocks sized by their length, overlapping ones sit side by side, and a red line marks the current time. Tasks sit in the all-day row.
  - Drag a task to another day to reschedule it. Drag an event onto the hour grid to change its day and time. Dropped on another day in the Month view, it keeps its time. While you drag, the item dims in place and a preview shows where it will land: an event block slides between 15-minute slots on the hour grid, and a chip follows the pointer over highlighted days.
  - Double-click a day to add a task due that day.
  - Show a "No Due Date" tray. Drag tasks from it onto a day, or drop a task on it to clear the due date.
- ⌘K search palette that jumps to tasks and views:
  - Typing searches task titles, task notes and views together.
  - Tab limits the search to tasks.
  - A leading `@` limits the search to views: `@today` (or `@daily`), `@upcoming`, `@done`, `@calendar`, `@month`, `@week`.
  - To search everything again, press Backspace in an empty field, press Tab again, or click ✕ on the scope token. Esc also removes a scope before it closes the palette.
- Click a task or event to edit its title, notes, due date or times in a popover
- Repeating tasks and events: pick Daily, Weekly, Monthly or Yearly under Repeat in the popover, with an interval (every 2 weeks), days of the week for weekly rules, and an optional end date.
  - Checking off a repeating task moves it to its next date that isn't in the past, unchecked and with its subtasks cleared. Once the rule has ended, it stays done.
  - A repeating event shows on every occurrence in the calendar, and once in lists, at its current or next occurrence. Edits, drags and deletes apply to the whole series: drag Wednesday's lecture to Thursday and every occurrence moves a day.
  - Rows, chips and event blocks show a ↻ icon. Hover over it for the rule.
- Subtasks: in a task's notes, start a line with `- [ ] ` (or `- [x] `) to turn it into a checkbox. Other lines stay plain notes.
  - Return adds the next subtask. Return or Backspace on an empty subtask deletes it and ends the list.
  - To delete any subtask, click the ✕ that shows when you hover over it or edit it, or right-click it.
  - Task rows show progress, such as `1/2`, and search also matches subtask titles.
- Autosave, undo/redo and File ▸ Revert To, all provided by the macOS document system

| Shortcut | Action |
|---|---|
| ⌘N | New task file |
| ⇧⌘N | New task |
| ⌥⌘N | New event |
| ⌘K | Search palette |
| Tab / @ | Search tasks / views (in the palette) |
| ↑ ↓ ↩ Esc | Move, open, close (in the palette) |
| Space | Toggle done on the selected tasks (events are skipped) |
| ⌫ | Delete the selected tasks |
| ⌘1–⌘9 | Select the 1st–9th task (list views) |
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
    },
    {
      "id": "9D4E2A71-6B3C-4F5D-8E90-1B2C3D4E5F03",
      "title": "Stretch",
      "notes": "",
      "done": false,
      "due": "2026-09-16",
      "repeat": { "frequency": "daily" },
      "createdAt": "2026-09-15T09:00:00Z"
    },
    {
      "id": "5C2F8B14-3E6A-4D7B-8F90-1A2B3C4D5E02",
      "title": "ML lecture",
      "notes": "Room F073",
      "start": "2026-09-22T09:00:00+09:00",
      "end": "2026-09-22T10:15:00+09:00",
      "repeat": { "frequency": "weekly", "weekdays": ["tue", "thu"], "until": "2026-12-17" },
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
| `start` | ISO-8601 timestamp. Its presence makes the entry an event | none |
| `end` | ISO-8601 timestamp, after `start` | one hour after `start` |
| `repeat` | `{frequency, interval, weekdays, until}`, where only `frequency` is needed | none, and left out when there is no rule |
| `createdAt` | ISO-8601 timestamp | time of loading |

In `repeat`:
- `frequency` is `daily`, `weekly`, `monthly` or `yearly`.
- `interval` repeats every that many days, weeks, months or years. It defaults to 1 and is left out when 1.
- `weekdays` is for weekly rules only: `sun`, `mon`, `tue`, `wed`, `thu`, `fri`, `sat`. Without it, a weekly rule repeats on the weekday it starts.
- `until` is the last `yyyy-MM-dd` day an occurrence can fall on.

A task's rule moves its `due` along. An event's rule counts occurrences from its `start`, which is the first one, and each occurrence keeps the event's time of day and length. A monthly rule on the 31st falls on the last day of shorter months.

Events don't have `done` or `due`. The app writes their times with your local offset, such as `+09:00`, and reads any ISO-8601 offset or `Z`.

The file is meant to be edited by hand as well as by the app. `{"tasks": [{"title": "Buy milk"}]}` is a valid file.

The app writes JSON pretty-printed with sorted keys, so git diffs stay small.

When you edit a file in the app and save it, a few things are not kept:
- Unknown fields.
- Due dates that can't be parsed.
- Event times that can't be parsed. An entry with an unreadable `start` loads as a task.
- A `repeat` with a missing or unknown `frequency`, unknown weekday names, or an unreadable `until`.

## Architecture

```
Tasks/
  TasksApp.swift              DocumentGroup scene
  Document/TaskDocument.swift FileDocument: reads and writes JSON
  Model/                      TaskFile, TaskItem (tolerant Codable), Subtask + Checklist (`- [ ]` parsing),
                              Recurrence (repeat rules, occurrences),
                              TaskFilter (filter + sort),
                              CalendarGrid (month/week date math) + EventLayout (week grid placement),
                              CalendarDrop (drag target under the pointer),
                              SearchPalette (query parsing + result ranking)
  Views/                      ContentView (split view), TaskRow, TaskDetailView (popover),
                              NotesEditor (subtask checklist + notes), WindowKeyMonitor
  Views/Calendar/             CalendarView, MonthGridView, WeekView, TaskChip, UndatedTray,
                              CalendarDragging (live drag state, drop zones, previews)
  Views/Search/               SearchPaletteView (⌘K palette)
  Updates/                    CheckForUpdatesView (Sparkle menu item)
  AppIcon.icon                Icon Composer app icon
scripts/                      release.sh (sign, notarize, publish), ExportOptions.plist
TasksTests/                   Swift Testing: coding round-trips, filters, sorting, calendar grid,
                              event layout and moves, repeat rules, palette search
```

All edits go through the document binding. That binding records undo and marks the file dirty, so there is no separate state store.

## Build

Requires Xcode 26 or later and macOS 26 or later.

```sh
open Tasks.xcodeproj          # then ⌘R
xcodebuild test -scheme Tasks -destination 'platform=macOS'
```

## Install

Download `K2Tasks-x.y.z.zip` from [Releases](https://github.com/kaunghko/Tasks/releases), unzip it, and drag `K2Tasks.app` into `/Applications`. Builds are signed with Developer ID and notarized by Apple, so they open without warnings. After that, the app checks for updates once a day and can install them itself. You can also use K2Tasks ▸ Check for Updates….

Maintainers: see [RELEASING.md](RELEASING.md).
