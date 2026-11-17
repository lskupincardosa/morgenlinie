import Foundation

/// Everything that points at the outside world lives here.
enum AppConfig {
    static let defaultBaseURL = URL(string: "https://morgenlinie.lskupincardosa.workers.dev/")!
    /// UserDefaults key for an archive address set in Settings.
    static let baseURLKey = "archiveBaseURL"

    /// The archive the app syncs from: the one set in Settings, else the default.
    static var baseURL: URL {
        #if DEBUG
        // For testing against a local copy: MORGENLINIE_BASE_URL=http://localhost:8000/
        if let override = ProcessInfo.processInfo.environment["MORGENLINIE_BASE_URL"], let url = URL(string: override) {
            return url
        }
        #endif
        return UserDefaults.standard.string(forKey: baseURLKey).flatMap(normalizedBaseURL) ?? defaultBaseURL
    }
    static var manifestURL: URL { baseURL.appending(path: "editions.json") }
    static var isUsingDefaultBaseURL: Bool { baseURL == defaultBaseURL }

    /// Accepts "example.com", "https://example.com" or ".../editions.json"; returns an http(s)
    /// URL ending in "/", or nil.
    static func normalizedBaseURL(_ text: String) -> URL? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if !t.contains("://") { t = "https://" + t }
        if t.hasSuffix("editions.json") { t.removeLast("editions.json".count) }
        if !t.hasSuffix("/") { t += "/" }
        guard let url = URL(string: t), ["http", "https"].contains(url.scheme?.lowercased()), url.host() != nil else { return nil }
        return url
    }
    static let supportedSchemaVersion = 1

    /// Must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
    static let refreshTaskID = "tech.flyingant.morgenlinie.refresh"
    /// The export lands at about 07:50 Berlin; ask iOS to wake us a little later.
    static let refreshTime = DateComponents(hour: 7, minute: 55)
    static let editionTimeZone = TimeZone(identifier: "Europe/Berlin")!

    static func webURL(forEditionPath path: String) -> URL {
        baseURL.appending(path: path)
    }
}
