import Foundation
import SwiftData

@Model
final class Edition {
    /// ISO date, e.g. "2026-11-11". Sorts chronologically as a string.
    @Attribute(.unique) var date: String
    var topic: String?
    var sha256: String
    /// File name inside EditionStore.directory.
    var localFile: String
    var downloadedAt: Date
    var isRead: Bool
    /// First lead story headline, parsed at sync time (archive rows, notifications).
    var leadHeadline: String?

    init(date: String, topic: String?, sha256: String, localFile: String,
         downloadedAt: Date = .now, isRead: Bool = false, leadHeadline: String? = nil) {
        self.date = date
        self.topic = topic
        self.sha256 = sha256
        self.localFile = localFile
        self.downloadedAt = downloadedAt
        self.isRead = isRead
        self.leadHeadline = leadHeadline
    }

    var fileURL: URL { EditionStore.directory.appending(path: localFile) }
    var webURL: URL { AppConfig.webURL(forEditionPath: "editions/\(date).html") }
    /// Noon on that calendar day in the current time zone, for display only.
    var day: Date { EditionDate.date(from: date) ?? .distantPast }
    var monthKey: String { String(date.prefix(7)) }
}

enum EditionDate {
    static func date(from iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    static func isValid(_ iso: String) -> Bool {
        iso.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil && date(from: iso) != nil
    }

    /// "Wednesday 11 November", as in the edition header. Used in notifications.
    static func longTitle(_ iso: String) -> String {
        guard let d = date(from: iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = Calendar.current.timeZone
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: d)
    }
}
