import SwiftUI
import WebKit

enum ReaderTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    static let storageKey = "theme"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    /// Value for <html data-theme>; nil lets the page follow prefers-color-scheme.
    var dataTheme: String? { self == .system ? nil : rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Decides what happens with links: in-page anchors stay, http(s) goes to Safari.
@MainActor
final class LinkPolicy {
    var documentURL: URL?
    var openExternal: (URL) -> Void = { _ in }

    func isSameDocument(_ url: URL) -> Bool {
        guard let documentURL else { return false }
        return url.withoutFragment == documentURL.withoutFragment
    }
}

struct LinkDecider: WebPage.NavigationDeciding {
    let policy: LinkPolicy

    mutating func decidePolicy(for action: WebPage.NavigationAction,
                               preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about" || policy.isSameDocument(url) { return .allow }
        // Story links (target="_blank" or not) never navigate the reader.
        if action.navigationType == .linkActivated || action.target == nil {
            if scheme == "http" || scheme == "https" {
                policy.openExternal(url)
            } else if scheme == "mailto" || scheme == "tel" {
                await UIApplication.shared.open(url)
            }
        }
        return .cancel
    }
}

@MainActor @Observable
final class ReaderWebModel {
    let page: WebPage
    private let policy: LinkPolicy
    private var loadedKey: String?

    init() {
        let policy = LinkPolicy()
        self.policy = policy
        page = WebPage(navigationDecider: LinkDecider(policy: policy))
    }

    func setExternalLinkHandler(_ handler: @escaping (URL) -> Void) {
        policy.openExternal = handler
    }

    /// Loads the local file with the edition's public URL as base, so anchors and fonts resolve normally.
    func show(_ edition: Edition, theme: ReaderTheme) {
        let key = "\(edition.date)|\(edition.sha256)|\(theme.rawValue)"
        guard key != loadedKey else { return }
        loadedKey = key
        let html: String
        do {
            html = try String(contentsOf: edition.fileURL, encoding: .utf8)
        } catch {
            html = "<meta name=viewport content='width=device-width'><p style='font:17px -apple-system;padding:24px'>This edition's file is missing. Pull to refresh in the archive to download it again.</p>"
        }
        policy.documentURL = edition.webURL
        _ = page.load(html: EditionHTML.addingAppStyle(to: EditionHTML.applyingTheme(theme.dataTheme, to: html)),
                      baseURL: edition.webURL)
    }

    /// Makes the next `show` load the page again, even for the same edition.
    func forget() {
        loadedKey = nil
    }

    func jump(to sectionID: String) async {
        _ = try? await page.callJavaScript(
            "const el = document.getElementById(id); if (el) { el.scrollIntoView({behavior: 'smooth'}); history.replaceState(null, '', '#' + id) }",
            arguments: ["id": sectionID])
    }
}

private extension URL {
    var withoutFragment: String {
        var c = URLComponents(url: self, resolvingAgainstBaseURL: false)
        c?.fragment = nil
        return c?.string ?? absoluteString
    }
}
