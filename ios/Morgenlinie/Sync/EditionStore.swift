import CryptoKit
import Foundation

/// HTML files in Application Support/Editions/YYYY-MM-DD.html.
enum EditionStore {
    static let directory: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "Editions", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func fileName(for date: String) -> String { "\(date).html" }

    static func write(_ data: Data, for date: String) throws -> String {
        let name = fileName(for: date)
        try data.write(to: directory.appending(path: name), options: .atomic)
        return name
    }

    static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: name).path(percentEncoded: false))
    }

    static func removeAll() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func bytesUsed() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])) ?? []
        return files.reduce(0) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
    }
}
