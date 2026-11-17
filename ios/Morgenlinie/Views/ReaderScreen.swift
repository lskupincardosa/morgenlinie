import SafariServices
import SwiftUI
import WebKit

/// Shows one edition with previous/next day and a section menu. `editions` is newest first.
struct ReaderScreen: View {
    let editions: [Edition]
    @Binding var date: String
    /// A reader owned by someone else keeps its page when this view is rebuilt.
    var sharedWeb: ReaderWebModel?

    @AppStorage(ReaderTheme.storageKey) private var theme: ReaderTheme = .system
    @State private var ownWeb: ReaderWebModel?
    @State private var sections: [EditionHTML.Section] = []
    @State private var safariURL: IdentifiableURL?

    private var web: ReaderWebModel? { sharedWeb ?? ownWeb }
    private var index: Int? { editions.firstIndex { $0.date == date } }
    private var edition: Edition? { index.map { editions[$0] } }
    private var older: Edition? { index.flatMap { $0 + 1 < editions.count ? editions[$0 + 1] : nil } }
    private var newer: Edition? { index.flatMap { $0 > 0 ? editions[$0 - 1] : nil } }

    var body: some View {
        Group {
            if let web {
                WebView(web.page)
                    .webViewLinkPreviews(.disabled)
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            } else {
                Color.clear
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button("Previous day", systemImage: "chevron.left") { older.map { date = $0.date } }
                    .disabled(older == nil)
                Button("Next day", systemImage: "chevron.right") { newer.map { date = $0.date } }
                    .disabled(newer == nil)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Sections", systemImage: "list.bullet") {
                    ForEach(sections) { section in
                        Button(section.title) { Task { await web?.jump(to: section.id) } }
                    }
                }
                .disabled(sections.isEmpty)
            }
            if let edition {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: edition.webURL)
                }
            }
        }
        .onAppear {
            if web == nil { ownWeb = ReaderWebModel() }
            web?.setExternalLinkHandler { safariURL = IdentifiableURL(url: $0) }
            load()
        }
        .onChange(of: date) { load() }
        .onChange(of: edition?.sha256) { load() }
        .onChange(of: theme) { load() }
        .sheet(item: $safariURL) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
    }

    private func load() {
        guard let edition, let web else { return }
        web.show(edition, theme: theme)
        sections = (try? String(contentsOf: edition.fileURL, encoding: .utf8)).map(EditionHTML.sections(in:)) ?? []
        if !edition.isRead { edition.isRead = true }
    }
}

struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct SafariView: UIViewControllerRepresentable {
    /// Settings toggle: open articles in Safari's Reader view (text and pictures, no ads).
    static let readerKey = "openLinksInReader"

    let url: URL
    @AppStorage(SafariView.readerKey) private var useReader = true

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        // Falls back to the normal page when a site has no Reader view (e.g. some paywalls).
        config.entersReaderIfAvailable = useReader
        return SFSafariViewController(url: url, configuration: config)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
