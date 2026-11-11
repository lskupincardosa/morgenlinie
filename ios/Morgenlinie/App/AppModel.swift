import Foundation
import Observation
import SwiftData

enum AppTab: Hashable { case today, archive, settings }

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    let container: ModelContainer
    let sync = EditionSync()

    var selectedTab: AppTab = .today
    /// The edition shown in the Today tab; nil means the newest one.
    var todayDate: String?

    private init() {
        do {
            container = try ModelContainer(for: Edition.self)
        } catch {
            fatalError("Could not open the edition database: \(error)")
        }
    }

    func refresh(fromBackground: Bool = false) async {
        let context = container.mainContext
        let hadEditions = ((try? context.fetchCount(FetchDescriptor<Edition>())) ?? 0) > 0
        let newDates = await sync.run(context: context)
        // Ask once, after the first edition is on screen. Asking at launch would make the
        // scene inactive and delay the first sync until the alert is answered.
        if !fromBackground, !newDates.isEmpty || hadEditions, Notifier.isEnabled,
           !UserDefaults.standard.bool(forKey: "askedForNotifications") {
            UserDefaults.standard.set(true, forKey: "askedForNotifications")
            await Notifier.requestAuthorization()
        }
        guard let newest = newDates.first else { return }
        todayDate = nil
        // No notification for the initial download after install.
        if fromBackground, hadEditions {
            let edition = try? context.fetch(FetchDescriptor<Edition>(predicate: #Predicate { $0.date == newest })).first
            await Notifier.postNewEdition(date: newest, topic: edition?.topic, headline: edition?.leadHeadline)
        }
    }

    func open(date: String?) {
        selectedTab = .today
        todayDate = date
    }
}
