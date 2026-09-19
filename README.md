# K2Tasks

A native macOS task manager that renders a plain `.json` file.

- The file is the source of truth, the way Obsidian treats `.md` files.
- No database, no account.
- To sync or back up, keep the file somewhere that already does: iCloud Drive, Dropbox or a git repo.
- Built with Swift and SwiftUI. Only dependency: [Sparkle](https://sparkle-project.org), for in-app updates.

## Features

### Files
- Open any `.json` task list: File ▸ Open, Open Recent, or Finder ▸ Open With ▸ K2Tasks.
- Autosave, undo/redo and File ▸ Revert To, all from the macOS document system.

### Lists
- Sidebar filters: All, Today (includes overdue), Upcoming, Completed.
- The sidebar is hidden by default. Show it with the toolbar button.
- A new task or event closed without changes is removed (Esc, clicking elsewhere, or opening another task). A mistaken click leaves nothing behind.

### Task details
- Click a task or event in a list to expand it in place, with the caret where you clicked.
- Edit its title, notes, subtasks, due date or times, repeat rule and alert.
- Esc or a click outside closes it.
- The list keeps its order while a task is open, and re-sorts after.
- On the calendar, the same fields open in a popover.

### Due times
- A task can have a due time as well as a due date (Time under Due Date).
- Rows and calendar chips show it, such as `Tomorrow · 08:00`.
- Timed tasks sort by time within a day.

### Events
- Events have start and end times and live next to tasks.
- Add one by:
  - pressing ⌥⌘N
  - dragging from start to end time on the Week view's hour grid
  - double-clicking the hour grid (one-hour event)
  - switching a task to Event in its details
- Switching kinds:
  - Event → task: the event's start becomes the task's due time.
  - Timed task → event: the event starts at that time.
  - Switching back and forth keeps the event's times and the task's done state.
- Events show a colored bar instead of a checkbox, plus their time range, such as `09:00–10:15`.
- Today lists events that haven't ended yet.
- Past events fade and never count as completed.

### Calendar
Month and Week views, similar to Calendar.app.

- **Week view**
  - Hourly grid with a red line at the current time.
  - Events are blocks sized by their length. Overlapping ones sit side by side.
  - Tasks with a due time sit on the grid at that time and take up half an hour.
  - Other tasks sit in the all-day row.
- **Dragging**
  - Drag a task to another day to reschedule it.
  - Drag an event or task onto the hour grid to change its day and time. An untimed task gets a due time.
  - Drop a timed task on the all-day row to remove its time.
  - In the Month view, an item dropped on another day keeps its time.
  - While dragging, the item dims in place and a preview shows where it lands:
    - on the hour grid, a block slides between 15-minute slots
    - elsewhere, a chip follows the pointer over highlighted days
- **Other**
  - Double-click a day to add a task due that day.
  - "No Due Date" tray: drag tasks from it onto a day, or drop a task on it to clear its due date.

### Search palette (⌘K)
- Jumps to tasks and views.
- Typing searches task titles, notes, subtask titles and views together.
- Tab limits the search to tasks.
- A leading `@` limits it to views: `@today` (or `@daily`), `@upcoming`, `@done`, `@calendar`, `@month`, `@week`.
- To search everything again: Backspace in an empty field, Tab again, or ✕ on the scope token.
- Esc removes a scope first, then closes the palette.

### Typing dates into titles
Type a date, time, repeat rule or alert into a title and the details pick it up (English only).

- **Understands**
  - Days: `today`, `tonight`, `tomorrow`, `friday`, `next fri`, `in 3 days`, `next week`, `sep 22`, `9/22`, `2026-09-22`
  - Times: `3pm`, `15:30`, `noon`, `at 3`, `by 5pm`, `3-4pm`, `from 9 to 10:15`, `for 2 hours`
  - Repeat: `daily`, `every other week`, `every weekday`, `every mon wed`, `on sundays`, `every month on the 1st`, `every sep 22`, `until dec 17`
  - Alerts: `remind me 10 min before`, `notify 1h before`, `alert me the day before`, `remind me`, `no reminder`, `don't remind me`
- **Rules**
  - Alerts only go before the time. "remind me 10 min after" isn't picked up.
  - A plain "remind me" before "to" or "about" doesn't count: "Remind me to call mom" stays a title.
  - Weekday abbreviations like `sat` only count after `on`, `every`, `next`, `this`, `by` or `due`. "sat exam prep" stays a title.
  - A time from 1 to 6 without am/pm means the afternoon.
  - A time with no day means today.
- **Applying**
  - A row under the title shows what it found, such as "tomorrow → Tomorrow".
  - Nothing changes until you press Tab in the title, press ⌘↩ or click Apply. Click ✕ to ignore it.
  - Applying removes the phrase from the title. Undo reverts it in one step.
  - Applying never switches between task and event.
  - In a task, a time becomes the due time: "a new task tomorrow 8 am" → "a new task", due tomorrow at 08:00.
  - In an event, a time sets the start. A range ("3-4pm") or length ("for 2 hours") sets the end.

### Repeating tasks and events
- Under Repeat in the details: Daily, Weekly, Monthly or Yearly.
- Options: an interval (every 2 weeks), weekdays for weekly rules, an optional end date.
- Checking off a repeating task moves it to its next date that isn't in the past, unchecked and with subtasks cleared.
- Once the rule has ended, the task stays done.
- A repeating event shows on every occurrence in the calendar, and once in lists (current or next occurrence).
- Edits, drags and deletes apply to the whole series: drag Wednesday's lecture to Thursday and every occurrence moves a day.
- Rows, chips and event blocks show a ↻ icon. Hover over it for the rule.

### Notifications
- For events and timed tasks, at their time by default.
- Pick an earlier time or None under Alert in the details.
- Tasks with only a due date don't notify.
- macOS delivers them even when the app is closed.
- Scheduled for the next two weeks (up to 60) whenever a file opens or changes. A repeating event keeps notifying as long as you open its file now and then.
- macOS asks for permission the first time. Change it later in System Settings ▸ Notifications.

### Subtasks
- In a task's notes, start a line with `- [ ] ` (or `- [x] `) to make it a checkbox. Other lines stay plain notes.
- Return adds the next subtask.
- Return or Backspace on an empty subtask deletes it and ends the list.
- Delete any subtask with the ✕ shown on hover or while editing, or by right-clicking it.
- Task rows show progress, such as `1/2`.

## Shortcuts

| Shortcut | Action |
|---|---|
| ⌘N | New task |
| ⇧⌘N | New window (new task file) |
| ⌥⌘N | New event |
| ⌘K | Search palette |
| Tab or ⌘↩ | Apply the date or rule found in a title (task details) |
| Esc | Close an expanded task (list views) |
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
| `due` | `yyyy-MM-dd`, a local day, or an ISO-8601 timestamp for a task with a due time | none |
| `start` | ISO-8601 timestamp. Its presence makes the entry an event | none |
| `end` | ISO-8601 timestamp, after `start` | one hour after `start` |
| `repeat` | `{frequency, interval, weekdays, until}`, where only `frequency` is needed | none, and left out when there is no rule |
| `alert` | minutes before the time, such as `10`, or `"none"`. For events and tasks with a due time | at the time, and left out then |
| `createdAt` | ISO-8601 timestamp | time of loading |

### `repeat`
- `frequency`: `daily`, `weekly`, `monthly` or `yearly`.
- `interval`: every that many days, weeks, months or years. Defaults to 1, left out when 1.
- `weekdays`: weekly rules only. `sun`, `mon`, `tue`, `wed`, `thu`, `fri`, `sat`. Without it, a weekly rule repeats on the weekday it starts.
- `until`: the last `yyyy-MM-dd` day an occurrence can fall on.
- A task's rule moves its `due` along.
- An event's rule counts occurrences from its `start` (the first one). Each keeps the event's time of day and length.
- A monthly rule on the 31st falls on the last day of shorter months.

### Dates and times
- A task without a time writes `due` as a plain `yyyy-MM-dd`.
- A task with a due time writes `due` with your local offset, such as `"2026-09-22T08:00:00+09:00"`. It loads as that day at the same local time.
- Events don't have `done` or `due`.
- Event times are written with your local offset, such as `+09:00`. Any ISO-8601 offset or `Z` is read.

### Editing by hand
- The file is meant to be edited by hand as well as by the app.
- `{"tasks": [{"title": "Buy milk"}]}` is a valid file.
- The app writes pretty-printed JSON with sorted keys, so git diffs stay small.
- Saving from the app drops:
  - unknown fields
  - due dates that can't be parsed
  - event times that can't be parsed (an entry with an unreadable `start` loads as a task)
  - an `alert` that isn't a positive number or `"none"` (loads as at the time)
  - a `repeat` with a missing or unknown `frequency`, unknown weekday names, or an unreadable `until`

## Architecture

```
Tasks/
  TasksApp.swift              DocumentGroup scene
  Document/TaskDocument.swift FileDocument: reads and writes JSON
  Model/                      TaskFile, TaskItem (tolerant Codable), Subtask + Checklist (`- [ ]` parsing),
                              Recurrence (repeat rules, occurrences),
                              TaskFilter (filter + sort),
                              CalendarGrid (month/week date math) + EventLayout (week grid placement of events and timed tasks),
                              CalendarDrop (drag target under the pointer),
                              SearchPalette (query parsing + result ranking),
                              ScheduleParser (dates, times and repeat rules typed into titles),
                              TextHitTest (which character a click lands on),
                              TaskAlert + Reminders (which notifications to schedule)
  Notifications/              NotificationScheduler (syncs pending notifications per document)
  Views/                      ContentView (split view), TaskRow (expands in place), TaskDetailView (calendar popover),
                              NotesEditor (subtask checklist + notes), WindowKeyMonitor, Caret
  Views/Calendar/             CalendarView, MonthGridView, WeekView, TaskChip, UndatedTray,
                              CalendarDragging (live drag state, drop zones, previews)
  Views/Search/               SearchPaletteView (⌘K palette)
  Updates/                    CheckForUpdatesView (Sparkle menu item)
  AppIcon.icon                Icon Composer app icon
scripts/                      release.sh (sign, notarize, publish), ExportOptions.plist
TasksTests/                   Swift Testing: coding round-trips, filters, sorting, calendar grid,
                              event layout and moves, repeat rules, palette search, title parsing, reminders,
                              click-to-caret hit testing
```

- All edits go through the document binding.
- That binding records undo and marks the file dirty, so there is no separate state store.

## Build

Requires Xcode 26+ and macOS 26+.

```sh
open Tasks.xcodeproj          # then ⌘R
xcodebuild test -scheme Tasks -destination 'platform=macOS'
```

## Install

- Download `K2Tasks-x.y.z.zip` from [Releases](https://github.com/kaunghko/Tasks/releases).
- Unzip it and drag `K2Tasks.app` into `/Applications`.
- Builds are signed with Developer ID and notarized, so they open without warnings.
- The app checks for updates daily and can install them itself, or use K2Tasks ▸ Check for Updates….

Maintainers: see [RELEASING.md](RELEASING.md).
