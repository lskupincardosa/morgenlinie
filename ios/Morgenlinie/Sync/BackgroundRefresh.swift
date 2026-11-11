import BackgroundTasks
import Foundation

enum BackgroundRefresh {
    /// Next 07:55 Europe/Berlin. iOS decides when the task really runs.
    static func nextRefreshDate(after now: Date = .now) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = AppConfig.editionTimeZone
        return calendar.nextDate(after: now, matching: AppConfig.refreshTime, matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(6 * 3600)
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: AppConfig.refreshTaskID)
        request.earliestBeginDate = nextRefreshDate()
        // Fails in the simulator and when Background App Refresh is off; foreground sync still works.
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func handle() async {
        schedule()
        await AppModel.shared.refresh(fromBackground: true)
    }
}
