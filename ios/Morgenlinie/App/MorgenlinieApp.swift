import SwiftUI
import UserNotifications

@main
struct MorgenlinieApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    @AppStorage(ReaderTheme.storageKey) private var theme: ReaderTheme = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(theme.colorScheme)
        }
        .modelContainer(model.container)
        .backgroundTask(.appRefresh(AppConfig.refreshTaskID)) {
            await BackgroundRefresh.handle()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { await PushRegistration.refresh() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await PushRegistration.didReceive(token: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // No push (e.g. in the simulator); the background refresh still posts local notifications.
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let date = response.notification.request.content.userInfo["date"] as? String
        await MainActor.run { AppModel.shared.open(date: date) }
    }
}
