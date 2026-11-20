import Foundation
import Testing
@testable import CapeKit

/// Reading answers of the pling.com OCS API. The answers are made up, in the shape the API
/// sends (numbers sometimes as strings, HTML in descriptions, numbered download fields).

private func answer(_ entries: [[String: Any]], total: Any = 2) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["status": "ok", "statuscode": 100, "message": "",
                                                "totalitems": total, "itemsperpage": 40, "data": entries])
}

private var fullEntry: [String: Any] { [
    "id": "1234", "name": "Test &amp; Cursors", "personid": "someone",
    "summary": "Short", "description": "<p>Line one<br />Line &lt;two&gt;</p><ul><li>Point</li></ul>",
    "detailpage": "https://www.pling.com/p/1234",
    "previewpic1": "https://images.pling.com/cache/770x540-4/img/00/01/1234/a.png",
    "previewpic2": "http://images.pling.com/cache/770x540-4/img/00/01/1234/b.png",
    "smallpreviewpic1": "https://images.pling.com/cache/770x540-4/img/00/01/1234/a.png",
    "downloads": "1225883", "score": 87, "tags": "linux,GPLv3,cursor",
    "changed": "2026-11-19T20:31:07+00:00", "ghns_excluded": 0,
    "downloadname1": "Test-cursors.tar.xz", "downloadlink1": "https://files.pling.com/dl/1/Test-cursors.tar.xz",
    "downloadsize1": 167, "downloadmd5sum1": "773AE8CB0FC173312F03AFFAFBD8AA4E",
    "downloadname2": "../../.hidden/evil.zip", "downloadlink2": "https://files.pling.com/dl/2/evil.zip",
    "downloadsize2": "", "downloadmd5sum2": "not-a-checksum",
    "downloadname3": "plain.zip", "downloadlink3": "http://files.pling.com/dl/3/plain.zip",
] }

@Test func readsAThemeFromTheList() throws {
    let page = try PlingCatalog.page(from: answer([fullEntry]))
    #expect(page.totalCount == 2)
    let theme = try #require(page.themes.first)
    #expect(theme.id == 1234)
    #expect(theme.name == "Test & Cursors")
    #expect(theme.author == "someone")
    #expect(theme.description == "Line one\nLine <two>\n• Point")
    #expect(theme.downloads == 1_225_883)
    #expect(theme.score == 87)
    #expect(theme.licence == "GPL-3.0")
    #expect(theme.changed != nil)
    // Only HTTPS links; the small preview from the image cache's smaller size.
    #expect(theme.previews.count == 1)
    #expect(theme.thumbnail?.absoluteString == "https://images.pling.com/cache/280x171/img/00/01/1234/a.png")
    #expect(theme.files.map(\.id) == [1, 2])
    #expect(theme.files[0].size == 167 * 1024)
    #expect(theme.files[0].md5 == "773ae8cb0fc173312f03affafbd8aa4e")
    // A name from the catalogue never leaves the download folder, nor hides.
    #expect(theme.files[1].name == "evil.zip")
    #expect(theme.files[1].size == nil)
    #expect(theme.files[1].md5 == nil)
}

/// Themes the catalogue keeps out of apps aren't offered; entries without an id or a name
/// are skipped.
@Test func leavesOutExcludedAndBrokenThemes() throws {
    var excluded = fullEntry
    excluded["ghns_excluded"] = "1"
    let page = try PlingCatalog.page(from: answer([excluded, ["id": 5], ["name": "No id"]], total: "3"))
    #expect(page.themes.isEmpty)
    #expect(page.entryCount == 3)
    #expect(page.totalCount == 3)
}

@Test func readsTheSingleThemeAnswer() throws {
    let data = try JSONSerialization.data(withJSONObject: ["status": "ok", "statuscode": 100, "message": "",
                                                           "data": [fullEntry]])
    #expect(try PlingCatalog.page(from: data).themes.map(\.id) == [1234])
}

@Test func reportsRefusalsAndGarbage() throws {
    let refused = try JSONSerialization.data(withJSONObject: ["status": "failed", "statuscode": 999, "message": "unknown request"])
    #expect(throws: PlingCatalog.CatalogError.refused("unknown request")) { try PlingCatalog.page(from: refused) }
    #expect(throws: PlingCatalog.CatalogError.unreadable) { try PlingCatalog.page(from: Data("<html>".utf8)) }
}

@Test func buildsRequests() throws {
    let url = PlingCatalog.listURL(search: "  bibata ice ", sort: .newest, page: 2)
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    let values = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    #expect(url.scheme == "https")
    #expect(values["categories"] == "107")
    #expect(values["sortmode"] == "new")
    #expect(values["page"] == "2")
    #expect(values["search"] == "bibata ice")
    #expect(!PlingCatalog.listURL().absoluteString.contains("search"))
    #expect(PlingCatalog.themeURL(id: 42).absoluteString.hasSuffix("/content/data/42?format=json"))
}

@Test(arguments: [("a/b/c.tar.gz", "c.tar.gz"), ("..", "download"), (".x.zip", "x.zip"),
                  ("~/t.zip", "t.zip"), ("a\u{0}b:c.zip", "abc.zip"), ("", "download")])
func cleansFileNames(name: String, expected: String) {
    #expect(PlingTheme.File.safeName(name) == expected)
}

@Test func decodesEntities() {
    #expect(PlainText.from(html: "A&#39;s &#x263A; &bogus; & done") == "A's ☺ &bogus; & done")
}

private func file(_ id: Int, _ name: String, md5: String?) -> PlingTheme.File {
    PlingTheme.File(id: id, name: name, url: URL(string: "https://files.pling.com/\(id)")!, size: nil, md5: md5)
}

/// An update is a changed checksum under the installed name, or the single file of a theme
/// whose installed file is gone; with several variants, a new name says nothing.
@Test func findsUpdates() throws {
    let theme = try #require(try PlingCatalog.page(from: answer([fullEntry])).themes.first)
    let same = [file(1, "Sweet.tar.xz", md5: "aa"), file(2, "Sweet-white.tar.xz", md5: "bb")]
    #expect(theme.updatedFile(installedName: "Sweet.tar.xz", installedMD5: "aa", among: same) == nil)
    let changed = [file(1, "Sweet.tar.xz", md5: "cc"), file(2, "Sweet-white.tar.xz", md5: "bb")]
    #expect(theme.updatedFile(installedName: "Sweet.tar.xz", installedMD5: "aa", among: changed)?.md5 == "cc")
    // Renamed: only the single candidate counts.
    let renamed = [file(1, "Sweet-v2.tar.xz", md5: "dd")]
    #expect(theme.updatedFile(installedName: "Sweet.tar.xz", installedMD5: "aa", among: renamed)?.id == 1)
    let renamedVariants = [file(1, "Sweet-v2.tar.xz", md5: "dd"), file(2, "Sweet-white-v2.tar.xz", md5: "ee")]
    #expect(theme.updatedFile(installedName: "Sweet.tar.xz", installedMD5: "aa", among: renamedVariants) == nil)
    // Without checksums nothing can be told.
    #expect(theme.updatedFile(installedName: "Sweet.tar.xz", installedMD5: nil, among: changed) == nil)
    #expect(theme.updatedFile(installedName: "Sweet.tar.xz", installedMD5: "aa",
                              among: [file(1, "Sweet.tar.xz", md5: nil)]) == nil)
}

/// The source travels in the cape file; a broken one is kept as it was, not trusted.
@Test func capeSourceRoundTrips() throws {
    var cape = Cape(identifier: "local.sweet", name: "Sweet", author: "eliverlara")
    cape.source = CapeSource(site: "pling.com", themeID: 1393084, page: URL(string: "https://www.pling.com/p/1393084"),
                             fileName: "Sweet-cursors.tar.xz", md5: "773ae8cb0fc173312f03affafbd8aa4e")
    let read = try Cape(propertyListData: cape.propertyListData())
    #expect(read.source == cape.source)

    var plist = Cape(identifier: "local.x", name: "X", author: "").propertyList
    plist["Source"] = ["Site": "pling.com", "ID": "12", "Page": "http://evil.example", "File": "../a.zip", "MD5": "nope"]
    let loose = try Cape(propertyList: plist)
    #expect(loose.source == CapeSource(site: "pling.com", themeID: 12, page: nil, fileName: "a.zip", md5: nil))

    plist["Source"] = ["Site": "pling.com"]          // no id: not a source this version reads
    let unknown = try Cape(propertyList: plist)
    #expect(unknown.source == nil)
    #expect(try Cape(propertyListData: unknown.propertyListData()).propertyList["Source"] as? [String: String] == ["Site": "pling.com"])
}
