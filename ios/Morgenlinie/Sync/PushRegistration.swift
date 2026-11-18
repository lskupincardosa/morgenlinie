import Foundation
import UIKit
import UserNotifications

/// Registers this iPhone with the archive's Worker (POST /push/register), which sends a push
/// notification as soon as a new edition is published. The background refresh in
/// BackgroundRefresh stays as a fallback; Notifier skips its local notification when the
/// push for that date has already arrived.
@MainActor
enum PushRegistration {
    private static let tokenKey = "pushDeviceToken"
    private static let registeredBaseURLKey = "pushRegisteredBaseURL"

    /// Asks iOS for a device token if notifications are allowed. iOS answers through
    /// AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:).
    static func refresh() async {
        guard Notifier.isEnabled else {
            await unregister()
            return
        }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard [.authorized, .provisional, .ephemeral].contains(status) else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Sends the token to the Worker. Called on every launch, since tokens can change.
    static func didReceive(token data: Data) async {
        let token = data.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: tokenKey)
        guard Notifier.isEnabled else { return }
        let base = AppConfig.baseURL
        if await post(to: base, path: "push/register", body: ["token": token, "env": apnsEnvironment]) {
            UserDefaults.standard.set(base.absoluteString, forKey: registeredBaseURLKey)
        }
    }

    /// Removes this iPhone from the Worker it registered with, e.g. when notifications are
    /// switched off or before moving to another archive.
    static func unregister() async {
        guard let token = UserDefaults.standard.string(forKey: tokenKey),
              let base = UserDefaults.standard.string(forKey: registeredBaseURLKey).flatMap(URL.init(string:))
        else { return }
        if await post(to: base, path: "push/unregister", body: ["token": token]) {
            UserDefaults.standard.removeObject(forKey: registeredBaseURLKey)
        }
    }

    /// Builds run from Xcode get sandbox tokens, TestFlight and App Store builds production ones.
    /// A Release build from Xcode is still sandbox; the Worker notices and switches hosts.
    private static var apnsEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    private static func post(to base: URL, path: String, body: [String: String]) async -> Bool {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        request.timeoutInterval = 15
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}
