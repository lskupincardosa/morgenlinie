import Foundation

/// editions.json, schemaVersion 1. See the repo README.
struct Manifest: Decodable, Sendable {
    struct Entry: Decodable, Sendable, Equatable {
        let date: String
        let path: String
        let topic: String?
        let sha256: String
        let bytes: Int
    }

    let schemaVersion: Int
    let updatedAt: String?
    let editions: [Entry]

    /// Decoded first, so a future format we can't read is still recognised as "newer".
    struct VersionProbe: Decodable { let schemaVersion: Int }
}

extension Manifest.Entry {
    /// Only accept paths the archive script produces; never write outside our folder.
    var isWellFormed: Bool {
        EditionDate.isValid(date) && path == "editions/\(date).html"
            && sha256.wholeMatch(of: /[0-9a-f]{64}/) != nil
    }
}
