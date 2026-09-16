import CoreGraphics
import Foundation

/// A place in the calendar that accepts dragged tasks. Frames are reported in one shared
/// coordinate space, so a drag can cross from one zone to another.
enum CalendarDropZone: Hashable {
    /// A month cell or the Week view's all-day row: moves to that day.
    case day(Date)
    /// A day column of the Week view's hour grid.
    case timeline(Date)
    /// The "No Due Date" tray.
    case undated
}

/// Where a drag would land if it ended now.
enum CalendarDropTarget: Equatable {
    case day(Date)
    /// An event's new start, as a day and a minute of that day.
    case time(day: Date, minute: Int)
    case undated

    /// The day (or column) to highlight.
    var day: Date? {
        switch self {
        case .day(let day), .time(let day, _): day
        case .undated: nil
        }
    }
}

enum CalendarDrop {
    /// The drop target under the pointer.
    /// - Parameters:
    ///   - grabOffsetY: How far below the dragged item's top the pointer grabbed it, so an event
    ///     keeps its position under the pointer instead of jumping its start to the pointer.
    static func target(
        at point: CGPoint,
        zones: [CalendarDropZone: CGRect],
        isEvent: Bool,
        grabOffsetY: CGFloat,
        hourHeight: CGFloat
    ) -> CalendarDropTarget? {
        // Day cells, the all-day row and the tray come first: the hour grid's frame runs on
        // under them when it's scrolled.
        for (zone, frame) in zones where frame.contains(point) {
            switch zone {
            case .day(let day): return .day(day)
            // Events always keep a date.
            case .undated: return isEvent ? nil : .undated
            case .timeline: continue
            }
        }
        for (zone, frame) in zones where frame.contains(point) {
            guard case .timeline(let day) = zone else { continue }
            guard isEvent else { return .day(day) }
            let minute = startMinute(topY: point.y - grabOffsetY - frame.minY, hourHeight: hourHeight)
            return .time(day: day, minute: minute)
        }
        return nil
    }

    /// The start minute for an event whose top edge is `topY` below midnight on the grid,
    /// rounded to the nearest 15 minutes and kept within the day.
    static func startMinute(topY: CGFloat, hourHeight: CGFloat) -> Int {
        guard hourHeight > 0 else { return 0 }
        let step = Double(EventLayout.snapMinutes)
        let minute = Int((Double(topY / hourHeight) * 60 / step).rounded()) * EventLayout.snapMinutes
        return min(max(minute, 0), EventLayout.minutesPerDay - EventLayout.snapMinutes)
    }
}
