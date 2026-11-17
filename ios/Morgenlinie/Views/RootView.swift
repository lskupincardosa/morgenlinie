import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.verticalSizeClass) private var heightClass
    @State private var foldOffset: CGFloat?

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Today", systemImage: "newspaper", value: AppTab.today) { TodayView() }
            Tab("Archive", systemImage: "calendar", value: AppTab.archive) { ArchiveView() }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) { SettingsView() }
        }
        .environment(\.readingLayout, ReadingLayout(
            isWide: foldOffset != nil || (widthClass == .regular && heightClass == .regular),
            foldOffset: foldOffset))
        .onGeometryChange(for: CGFloat?.self, of: ReadingLayout.verticalFoldOffset) { foldOffset = $0 }
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
    @Environment(\.readingLayout) private var layout
    @Query(sort: \Edition.date, order: .reverse) private var editions: [Edition]

    var body: some View {
        if layout.isWide {
            EditionColumns(title: "Editions", editions: editions,
                           selection: Binding(get: { date }, set: { select($0) }),
                           web: model.todayReader)
        } else {
            NavigationStack {
                if let date {
                    ReaderScreen(editions: editions, date: Binding(get: { date }, set: { select($0) }),
                                 sharedWeb: model.todayReader)
                } else {
                    EmptyArchiveView()
                }
            }
        }
    }

    /// `model.todayDate` if that edition exists, otherwise the newest one.
    private var date: String? {
        model.todayDate.flatMap { d in editions.contains { $0.date == d } ? d : nil } ?? editions.first?.date
    }

    private func select(_ date: String?) {
        model.todayDate = date == editions.first?.date ? nil : date
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
