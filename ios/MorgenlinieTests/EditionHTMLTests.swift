import Foundation
import Testing
@testable import Morgenlinie

struct EditionHTMLTests {
    let page = """
    <!doctype html><html><head></head><body>
    <nav class="route"><ol>
      <li><a href="#world" style="--c:var(--world)"><span class="bug">1</span>World</a></li>
      <li><a href="#topic" style="--c:var(--tech)"><span class="bug">6</span>Open source &amp; more</a></li>
    </ol></nav>
    <article class="story lead">
      <span class="kind">Reported by ZDFheute</span>
      <h3>Abu Dhabi talks: day one
        centred on a <em>large</em> prisoner swap</h3>
    </article>
    </body></html>
    """

    @Test func parsesSections() {
        let sections = EditionHTML.sections(in: page)
        #expect(sections.map(\.id) == ["world", "topic"])
        #expect(sections.map(\.title) == ["World", "Open source & more"])
    }

    @Test func parsesLeadHeadline() {
        #expect(EditionHTML.leadHeadline(in: page) == "Abu Dhabi talks: day one centred on a large prisoner swap")
    }

    @Test func appliesTheme() {
        #expect(EditionHTML.applyingTheme("dark", to: page).contains("<html data-theme=\"dark\"><head>"))
        #expect(EditionHTML.applyingTheme(nil, to: page) == page)
        let withLang = "<!doctype html><html lang=\"en\"><body></body></html>"
        #expect(EditionHTML.applyingTheme("light", to: withLang).contains("<html data-theme=\"light\" lang=\"en\">"))
    }

    @Test func validatesManifestEntries() throws {
        let json = #"""
        {"schemaVersion":1,"updatedAt":"2026-11-11T06:47:00Z","editions":[
          {"date":"2026-11-11","path":"editions/2026-11-11.html","topic":"Open source","sha256":"b2925dbf04ad5b2859232a25feaeb19071fc9d07eda6cd92e4b5654cc2c3940f","bytes":33005},
          {"date":"2026-11-10","path":"../evil.html","topic":null,"sha256":"b2925dbf04ad5b2859232a25feaeb19071fc9d07eda6cd92e4b5654cc2c3940f","bytes":1}
        ]}
        """#
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(json.utf8))
        #expect(manifest.editions.map(\.isWellFormed) == [true, false])
    }

    @Test func notificationDateTitle() {
        #expect(EditionDate.longTitle("2026-11-11") == "Wednesday 11 November")
    }

    @Test func nextRefreshIsBerlinMorning() {
        // 21:00 UTC on 11 Nov = 22:00 Berlin → next is 12 Nov 06:50 Berlin = 05:50 UTC.
        let now = ISO8601DateFormatter().date(from: "2026-11-11T21:00:00Z")!
        let next = BackgroundRefresh.nextRefreshDate(after: now)
        #expect(ISO8601DateFormatter().string(from: next) == "2026-11-12T05:50:00Z")
    }
}

struct AppConfigTests {
    @Test func normalizesArchiveAddresses() {
        #expect(AppConfig.normalizedBaseURL("example.com")?.absoluteString == "https://example.com/")
        #expect(AppConfig.normalizedBaseURL(" https://a.workers.dev/editions.json ")?.absoluteString == "https://a.workers.dev/")
        #expect(AppConfig.normalizedBaseURL("http://localhost:8000")?.absoluteString == "http://localhost:8000/")
        #expect(AppConfig.normalizedBaseURL("") == nil)
        #expect(AppConfig.normalizedBaseURL("ftp://x.org") == nil)
    }

    @Test func addsAppStyleInsideHead() {
        let out = EditionHTML.addingAppStyle(to: "<html><head><title>x</title></head><body></body></html>")
        #expect(out.contains("\(EditionHTML.appStyle)</head>"))
    }
}
