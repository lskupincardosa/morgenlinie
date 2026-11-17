import SwiftUI

/// Whether the edition list and the reader sit side by side.
///
/// Wide means a regular width and height (iPad, the unfolded iPhone Duo) or a window with a
/// vertical fold. iPhones never qualify (they are compact in at least one dimension and have no
/// fold), so they keep the single-column layout.
struct ReadingLayout: Equatable {
    var isWide = false
    /// Distance from the window's leading edge to the middle of a vertical fold, if there is one.
    /// The list ends there, so neither column crosses the fold.
    var foldOffset: CGFloat?

    /// The fold reported by the system (iOS 27.1+), in the global coordinate space.
    static func verticalFoldOffset(in proxy: GeometryProxy) -> CGFloat? {
        guard #available(iOS 27.1, *) else { return nil }
        let origin = proxy.frame(in: .global).minX
        return proxy.reservedRegions(kind: .division, options: .includeInactive)
            .first { $0.frame.height > $0.frame.width }
            .map { origin + $0.frame.midX }
    }
}

extension EnvironmentValues {
    @Entry var readingLayout = ReadingLayout()
}

/// The edition list and the reader as two columns for the wide layout.
///
/// Not a NavigationSplitView: it caps the sidebar at about 40% of the width (and hides it when
/// asked for more), so its edge can't be put on a fold in the middle of the screen. Its floating
/// sidebar also lets the web view run underneath and lay the page out for the whole window.
struct EditionColumns: View {
    let title: LocalizedStringKey
    let editions: [Edition]
    @Binding var selection: String?
    let web: ReaderWebModel

    @Environment(\.readingLayout) private var layout

    var body: some View {
        HStack(spacing: 0) {
            NavigationStack {
                ArchiveList(title: title, editions: editions, selection: $selection)
            }
            .frame(width: layout.foldOffset ?? 320)

            Divider().ignoresSafeArea()

            NavigationStack {
                if let date = selection {
                    ReaderScreen(editions: editions,
                                 date: Binding(get: { date }, set: { selection = $0 }),
                                 sharedWeb: web)
                } else if !editions.isEmpty {
                    ContentUnavailableView("Choose an edition", systemImage: "newspaper")
                }
            }
        }
    }
}
