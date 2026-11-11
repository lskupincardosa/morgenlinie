import Foundation

/// Everything that points at the outside world lives here.
enum AppConfig {
    static let baseURL: URL = {
        #if DEBUG
        // For testing against a local copy: MORGENLINIE_BASE_URL=http://localhost:8000/
        if let override = ProcessInfo.processInfo.environment["MORGENLINIE_BASE_URL"], let url = URL(string: override) {
            return url
        }
        #endif
        return URL(string: "https://lskupincardosa.github.io/morgenlinie/")!
    }()
    static let manifestURL = baseURL.appending(path: "editions.json")
    static let supportedSchemaVersion = 1

    /// Must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
    static let refreshTaskID = "com.lskupincardosa.morgenlinie.refresh"
    /// The export lands at about 07:50 Berlin; ask iOS to wake us a little later.
    static let refreshTime = DateComponents(hour: 7, minute: 55)
    static let editionTimeZone = TimeZone(identifier: "Europe/Berlin")!

    static func webURL(forEditionPath path: String) -> URL {
        baseURL.appending(path: path)
    }
}
