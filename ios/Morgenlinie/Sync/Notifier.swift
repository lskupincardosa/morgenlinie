import Foundation
import UserNotifications

enum Notifier {
    static let enabledKey = "notificationsEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// "Die Ausgabe für Mittwoch, 11. November ist da." No news in the notification itself.
    /// Keep in sync with editionPayload in src/worker.js (the push sent by the Worker).
    static func postNewEdition(date: String) async {
        guard isEnabled else { return }
        // The push from the Worker usually arrives first; don't announce the same edition twice.
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        if delivered.contains(where: { $0.request.content.userInfo["date"] as? String == date }) { return }
        let content = UNMutableNotificationContent()
        content.title = "Morgenlinie"
        content.body = "Die Ausgabe für \(EditionDate.germanTitle(date)) ist da."
        content.sound = .default
        content.userInfo = ["date": date]
        content.threadIdentifier = "editions"
        let request = UNNotificationRequest(identifier: "edition-\(date)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
