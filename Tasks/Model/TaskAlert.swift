import Foundation

/// When a timed task or an event notifies. Stored in JSON as `alert`: left out for `atTime`,
/// a number of minutes before, or `"none"`.
enum TaskAlert: Hashable, Codable {
    case atTime
    case minutesBefore(Int)
    case none

    /// The choices offered in the popover.
    static let presets: [TaskAlert] = [
        .atTime, .minutesBefore(5), .minutesBefore(10), .minutesBefore(15), .minutesBefore(30),
        .minutesBefore(60), .minutesBefore(24 * 60), .none,
    ]

    /// How long before the item's time the notification fires, or nil for no notification.
    var offset: TimeInterval? {
        switch self {
        case .atTime: 0
        case .minutesBefore(let minutes): TimeInterval(minutes * 60)
        case .none: nil
        }
    }

    /// "At time", "10 minutes before", "1 hour before", "1 day before", "None".
    var title: String {
        switch self {
        case .atTime: return "At time"
        case .none: return "None"
        case .minutesBefore(let minutes):
            if minutes > 0, minutes % (24 * 60) == 0 {
                let days = minutes / (24 * 60)
                return days == 1 ? "1 day before" : "\(days) days before"
            }
            if minutes > 0, minutes % 60 == 0 {
                let hours = minutes / 60
                return hours == 1 ? "1 hour before" : "\(hours) hours before"
            }
            return minutes == 1 ? "1 minute before" : "\(minutes) minutes before"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let minutes = try? container.decode(Int.self) {
            self = minutes > 0 ? .minutesBefore(minutes) : .atTime
        } else if try container.decode(String.self) == "none" {
            self = .none
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown alert")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .atTime: try container.encode(0)
        case .minutesBefore(let minutes): try container.encode(minutes)
        case .none: try container.encode("none")
        }
    }
}
