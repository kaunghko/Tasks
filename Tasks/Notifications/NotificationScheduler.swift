import Foundation
import UserNotifications

/// Keeps the system's pending notifications in step with each open document's `Reminders`.
/// macOS delivers them itself, so they fire even when the app is closed.
@MainActor
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    private var didRequestAuthorization = false

    /// Shows notifications while the app is frontmost too.
    func start() {
        center.delegate = self
    }

    /// Replaces the pending notifications of the document identified by `documentKey`.
    /// Other documents' notifications are left alone.
    func update(documentKey: String, reminders: [Reminder]) async {
        if !reminders.isEmpty, !didRequestAuthorization {
            // Asks the first time there's something to notify about, not at launch.
            didRequestAuthorization = true
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }

        let prefix = "\(documentKey)#"
        let wanted = Dictionary(reminders.map { (prefix + $0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }
        let stale = pending.map(\.identifier).filter { wanted[$0] == nil }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        // Adding with an existing identifier replaces it, which picks up title and time changes.
        let calendar = Calendar.current
        for (identifier, reminder) in wanted {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
