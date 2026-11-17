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
    /// The edition open in the Archive tab and the stack that led there. Kept here so they
    /// survive the layout change when an iPhone Duo is folded or unfolded.
    var archiveDate: String?
    var archivePath: [String] = []

    /// The readers outlive their views, so a rebuilt layout shows the same page at the same
    /// scroll position instead of loading it again.
    @ObservationIgnored lazy var todayReader = ReaderWebModel()
    @ObservationIgnored lazy var archiveReader = ReaderWebModel()

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

    /// Switches to another archive (nil = the default): removes the downloaded editions,
    /// since dates from two archives would collide, and syncs from the new address.
    func switchArchive(to url: URL?) async {
        if let url, url != AppConfig.defaultBaseURL {
            UserDefaults.standard.set(url.absoluteString, forKey: AppConfig.baseURLKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppConfig.baseURLKey)
        }
        let context = container.mainContext
        try? context.delete(model: Edition.self)
        try? context.save()
        EditionStore.removeAll()
        sync.resetCache()
        todayDate = nil
        archiveDate = nil
        archivePath = []
        todayReader.forget()
        archiveReader.forget()
        await refresh()
    }

    func open(date: String?) {
        selectedTab = .today
        todayDate = date
    }
}
