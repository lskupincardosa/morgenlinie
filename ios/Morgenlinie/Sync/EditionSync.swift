import Foundation
import Observation
import SwiftData

/// Pulls editions.json and downloads new or changed editions. Never deletes local editions.
@MainActor @Observable
final class EditionSync {
    private(set) var isSyncing = false
    private(set) var lastSuccess: Date?
    private(set) var lastError: String?
    /// The manifest uses a schemaVersion this build doesn't understand.
    private(set) var needsAppUpdate = false

    private let session: URLSession
    private let defaults: UserDefaults
    private let etagKey = "manifestETag"

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
        lastSuccess = defaults.object(forKey: "lastSyncSuccess") as? Date
    }

    /// Returns the dates of editions that were new on this device (newest first).
    @discardableResult
    func run(context: ModelContext) async -> [String] {
        guard !isSyncing else { return [] }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let new = try await perform(context: context)
            lastError = nil
            lastSuccess = .now
            defaults.set(lastSuccess, forKey: "lastSyncSuccess")
            return new
        } catch is CancellationError {
            return []
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    private func perform(context: ModelContext) async throws -> [String] {
        let local = try context.fetch(FetchDescriptor<Edition>())
        var byDate = Dictionary(local.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let localComplete = local.allSatisfy { EditionStore.exists($0.localFile) }

        var request = URLRequest(url: AppConfig.manifestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        if localComplete, let etag = defaults.string(forKey: etagKey) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        if http?.statusCode == 304 { return [] }
        guard http?.statusCode == 200 else { throw SyncError.http(http?.statusCode ?? -1) }

        let version = try JSONDecoder().decode(Manifest.VersionProbe.self, from: data).schemaVersion
        guard version <= AppConfig.supportedSchemaVersion else {
            needsAppUpdate = true
            return []
        }
        needsAppUpdate = false
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)

        var newDates: [String] = []
        var failures = 0
        for entry in manifest.editions where entry.isWellFormed {
            try Task.checkCancellation()
            if let existing = byDate[entry.date], existing.sha256 == entry.sha256, EditionStore.exists(existing.localFile) {
                continue
            }
            do {
                let html = try await download(entry)
                let file = try EditionStore.write(html, for: entry.date)
                let text = String(decoding: html, as: UTF8.self)
                if let existing = byDate[entry.date] {
                    existing.topic = entry.topic
                    existing.sha256 = entry.sha256
                    existing.localFile = file
                    existing.downloadedAt = .now
                    existing.leadHeadline = EditionHTML.leadHeadline(in: text)
                } else {
                    let edition = Edition(date: entry.date, topic: entry.topic, sha256: entry.sha256,
                                          localFile: file, leadHeadline: EditionHTML.leadHeadline(in: text))
                    context.insert(edition)
                    byDate[entry.date] = edition
                    newDates.append(entry.date)
                }
            } catch {
                failures += 1
            }
        }
        try context.save()

        if failures == 0, let etag = http?.value(forHTTPHeaderField: "ETag") {
            defaults.set(etag, forKey: etagKey)
        } else {
            defaults.removeObject(forKey: etagKey)
        }
        if failures > 0 { throw SyncError.downloads(failures) }
        return newDates.sorted(by: >)
    }

    private func download(_ entry: Manifest.Entry) async throws -> Data {
        let url = AppConfig.webURL(forEditionPath: entry.path)
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SyncError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        // Pages can briefly serve the old file after a push; we retry on the next sync.
        guard EditionStore.sha256(data) == entry.sha256 else { throw SyncError.checksum(entry.date) }
        return data
    }

    enum SyncError: LocalizedError {
        case http(Int), checksum(String), downloads(Int)
        var errorDescription: String? {
            switch self {
            case .http(let code): "The server answered with status \(code)."
            case .checksum(let date): "The edition for \(date) didn't match its checksum."
            case .downloads(let n): n == 1 ? "One edition couldn't be downloaded." : "\(n) editions couldn't be downloaded."
            }
        }
    }
}
