import Foundation

/// Small, forgiving parsers for the Morgenlinie page. The page has no JavaScript and a
/// stable structure, so regexes are enough; anything that doesn't match simply yields nothing.
enum EditionHTML {
    struct Section: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
    }

    /// Route navigation: <a href="#world" …><span class="bug">1</span>World</a>
    static func sections(in html: String) -> [Section] {
        let regex = /<a\s+href="#([\w-]+)"[^>]*>\s*<span class="bug">[^<]*<\/span>\s*([^<]+?)\s*<\/a>/
        var seen = Set<String>()
        return html.matches(of: regex).compactMap { m in
            let id = String(m.1)
            guard seen.insert(id).inserted else { return nil }
            return Section(id: id, title: decodeEntities(String(m.2)))
        }
    }

    /// First h3 inside the first lead story.
    static func leadHeadline(in html: String) -> String? {
        guard let lead = html.firstRange(of: #/<article class="story lead">/#) else { return nil }
        let rest = html[lead.upperBound...]
        guard let m = rest.firstMatch(of: /<h3[^>]*>(.*?)<\/h3>/.dotMatchesNewlines()) else { return nil }
        let text = decodeEntities(String(m.1).replacing(/<[^>]+>/, with: ""))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    /// Forces the page theme via <html data-theme="…">; nil keeps prefers-color-scheme.
    static func applyingTheme(_ theme: String?, to html: String) -> String {
        guard let theme, let tag = html.firstRange(of: /<html(?=[\s>])/.ignoresCase()) else { return html }
        var out = html
        out.replaceSubrange(tag, with: "<html data-theme=\"\(theme)\"")
        return out
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        return s.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
