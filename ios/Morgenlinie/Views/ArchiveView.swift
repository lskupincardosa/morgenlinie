import SwiftData
import SwiftUI

struct ArchiveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.readingLayout) private var layout
    @Query(sort: \Edition.date, order: .reverse) private var editions: [Edition]

    var body: some View {
        @Bindable var model = model
        Group {
            if layout.isWide {
                EditionColumns(title: "Archive", editions: editions, selection: $model.archiveDate,
                               web: model.archiveReader)
            } else {
                NavigationStack(path: $model.archivePath) {
                    ArchiveList(title: "Archive", editions: editions)
                        .navigationDestination(for: String.self) { opened in
                            ReaderScreen(editions: editions,
                                         date: Binding(get: { model.archiveDate ?? opened },
                                                       set: { model.archiveDate = $0 }),
                                         sharedWeb: model.archiveReader)
                        }
                }
            }
        }
        .onChange(of: model.archivePath) { _, path in
            model.archiveDate = path.last
            // Back in the list: the next edition opened starts at the top, as before.
            if path.isEmpty { model.archiveReader.forget() }
        }
        .onChange(of: layout.isWide) { _, isWide in
            // Folding keeps the edition that was open beside the list.
            if !isWide { model.archivePath = model.archiveDate.map { [$0] } ?? [] }
        }
    }
}

/// Editions grouped by month. `editions` is newest first.
struct ArchiveList: View {
    let title: LocalizedStringKey
    let editions: [Edition]
    /// With a selection, rows select an edition for the reader beside the list; without one,
    /// they push the reader.
    var selection: Binding<String?>?

    @Environment(AppModel.self) private var model

    private var months: [(key: String, editions: [Edition])] {
        var result: [(key: String, editions: [Edition])] = []
        for edition in editions {
            if result.last?.key == edition.monthKey {
                result[result.count - 1].editions.append(edition)
            } else {
                result.append((edition.monthKey, [edition]))
            }
        }
        return result
    }

    var body: some View {
        List(selection: selection) {
            if model.sync.needsAppUpdate {
                UpdateHint()
            }
            ForEach(months, id: \.key) { month in
                Section(month.editions[0].day.formatted(.dateTime.month(.wide).year())) {
                    ForEach(month.editions) { edition in
                        if selection == nil {
                            NavigationLink(value: edition.date) { ArchiveRow(edition: edition) }
                        } else {
                            ArchiveRow(edition: edition)
                                .tag(edition.date) // otherwise the month's ID is the selection
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .refreshable { await model.refresh() }
        .overlay {
            if editions.isEmpty { EmptyArchiveView() }
        }
    }
}

struct ArchiveRow: View {
    let edition: Edition

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(spacing: 0) {
                Text(edition.day.formatted(.dateTime.day()))
                    .font(.title2.monospacedDigit().weight(.semibold))
                Text(edition.day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption.smallCaps())
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(edition.leadHeadline ?? edition.day.formatted(date: .complete, time: .omitted))
                    .font(.body.weight(edition.isRead ? .regular : .semibold))
                    .lineLimit(2)
                Text(edition.topic ?? "Weekend edition")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !edition.isRead {
                Circle().fill(.tint).frame(width: 9, height: 9)
                    .accessibilityLabel("Unread")
            }
        }
        .padding(.vertical, 2)
    }
}

struct UpdateHint: View {
    var body: some View {
        Label("A newer archive format is available. Update the app to get new editions.",
              systemImage: "arrow.down.app")
            .font(.subheadline)
            .foregroundStyle(.orange)
    }
}
