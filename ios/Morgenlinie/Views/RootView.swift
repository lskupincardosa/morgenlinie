import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Today", systemImage: "newspaper", value: AppTab.today) { TodayView() }
            Tab("Archive", systemImage: "calendar", value: AppTab.archive) { ArchiveView() }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) { SettingsView() }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: Task { await model.refresh() }
            case .background: BackgroundRefresh.schedule()
            default: break
            }
        }
    }
}

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Edition.date, order: .reverse) private var editions: [Edition]

    var body: some View {
        NavigationStack {
            if let newest = editions.first {
                ReaderScreen(editions: editions, date: Binding(
                    get: { model.todayDate.flatMap { d in editions.contains { $0.date == d } ? d : nil } ?? newest.date },
                    set: { model.todayDate = $0 == newest.date ? nil : $0 }))
            } else {
                EmptyArchiveView()
            }
        }
    }
}

struct EmptyArchiveView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.sync.isSyncing {
            ProgressView("Loading editions…")
        } else {
            ContentUnavailableView {
                Label("No editions yet", systemImage: "newspaper")
            } description: {
                Text(model.sync.lastError ?? "The archive is empty. New editions arrive each morning.")
            } actions: {
                Button("Try again") { Task { await model.refresh() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
