import SwiftData
import SwiftUI

struct ArchiveView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Edition.date, order: .reverse) private var editions: [Edition]

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
        NavigationStack {
            List {
                if model.sync.needsAppUpdate {
                    UpdateHint()
                }
                ForEach(months, id: \.key) { month in
                    Section(month.editions[0].day.formatted(.dateTime.month(.wide).year())) {
                        ForEach(month.editions) { edition in
                            NavigationLink(value: edition.date) { ArchiveRow(edition: edition) }
                        }
                    }
                }
            }
            .navigationTitle("Archive")
            .navigationDestination(for: String.self) { date in
                ArchiveReader(editions: editions, initialDate: date)
            }
            .refreshable { await model.refresh() }
            .overlay {
                if editions.isEmpty { EmptyArchiveView() }
            }
        }
    }
}

private struct ArchiveReader: View {
    let editions: [Edition]
    @State private var date: String

    init(editions: [Edition], initialDate: String) {
        self.editions = editions
        _date = State(initialValue: initialDate)
    }

    var body: some View {
        ReaderScreen(editions: editions, date: $date)
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
