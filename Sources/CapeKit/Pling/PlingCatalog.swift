import Foundation

/// The cursor themes on pling.com (the catalogue behind gnome-look.org and store.kde.org),
/// read through its public OCS API, the one KDE's "Get New Stuff" uses. This part only
/// builds the requests and reads the answers; the app does the networking.
///
/// Everything in an answer is untrusted: names and descriptions are shown as plain text,
/// links must be HTTPS, file names are cleaned before they touch the disk, and themes the
/// catalogue keeps out of apps (`ghns_excluded`) are left out here too.
public enum PlingCatalog {
    /// The OCS category of cursor themes.
    public static let cursorCategory = 107
    static let apiBase = "https://api.pling.com/ocs/v1/content/data"
    /// Themes per page. The API returns at least 10.
    public static let pageSize = 40

    public enum Sort: String, CaseIterable, Identifiable, Sendable {
        case popular = "down"
        case newest = "new"         // by `created`
        /// By the last change. pling.com sorts by a time of its own, close to `changed`
        /// but not always the same: themes changed on nearby days can swap places.
        case updated = "update"
        case rating = "high"
        case name = "alpha"

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .popular: String(localized: "Most Downloaded")
            case .newest: String(localized: "Newest")
            case .updated: String(localized: "Recently Updated")
            case .rating: String(localized: "Highest Rated")
            case .name: String(localized: "Name")
            }
        }
    }

    /// One page of themes; `page` counts from 0.
    public static func listURL(search: String = "", sort: Sort = .popular, page: Int = 0) -> URL {
        var components = URLComponents(string: apiBase)!
        components.queryItems = [
            URLQueryItem(name: "categories", value: String(cursorCategory)),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "sortmode", value: sort.rawValue),
            URLQueryItem(name: "pagesize", value: String(pageSize)),
            URLQueryItem(name: "page", value: String(max(0, page))),
        ]
        let search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty { components.queryItems?.append(URLQueryItem(name: "search", value: search)) }
        return components.url!
    }

    /// One theme, for download links: they are signed and expire after a while, so they are
    /// fetched again right before a download.
    public static func themeURL(id: Int) -> URL {
        URL(string: "\(apiBase)/\(id)?format=json")!
    }

    public struct Page: Sendable {
        public let themes: [PlingTheme]
        /// All themes that match, on all pages.
        public let totalCount: Int
        /// Entries in the answer, including those left out; an empty page means the end.
        public let entryCount: Int
    }

    public enum CatalogError: LocalizedError, Equatable {
        case unreadable
        case refused(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "The answer from pling.com could not be read.")
            case .refused(let message): String(localized: "pling.com refused the request: \(message)")
            }
        }
    }

    /// Reads an answer of the list or the single theme request.
    public static func page(from data: Data) throws -> Page {
        guard let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CatalogError.unreadable
        }
        guard answer["status"] as? String == "ok" else {
            let message = (answer["message"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "\(answer["statuscode"] ?? "?")"
            throw CatalogError.refused(message)
        }
        let entries: [[String: Any]]
        if let list = answer["data"] as? [[String: Any]] {
            entries = list
        } else if let single = answer["data"] as? [String: Any] {
            entries = [single]
        } else {
            entries = []
        }
        let themes = entries.compactMap(PlingTheme.init(entry:)).filter { !$0.isExcludedFromApps }
        let total = integer(answer["totalitems"]) ?? themes.count
        return Page(themes: themes, totalCount: total, entryCount: entries.count)
    }

    /// The API sends numbers sometimes as numbers, sometimes as strings.
    static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
            let double = number.doubleValue
            return double.isFinite && abs(double) < 1e15 ? Int(double) : nil
        case let string as String:
            return Int(string.trimmingCharacters(in: .whitespaces))
        default:
            return nil
        }
    }

    static func string(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Only HTTPS links are followed.
    static func secureURL(_ value: Any?) -> URL? {
        guard let text = string(value), let url = URL(string: text), url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }
}

/// A cursor theme in the pling catalogue.
public struct PlingTheme: Identifiable, Hashable, Sendable {
    /// A file to download; most themes have one, some offer variants.
    public struct File: Identifiable, Hashable, Sendable {
        /// Its number in the entry (1, 2, …).
        public let id: Int
        /// The name as given by the catalogue, cleaned (see `safeName`).
        public let name: String
        public let url: URL
        /// In bytes, as the catalogue gives it (it counts in kilobytes); nil when unknown.
        public let size: Int?
        /// Lower-case hex, to check the download; nil when the catalogue gives none.
        public let md5: String?
    }

    public let id: Int
    public let name: String
    public let author: String
    /// Plain text, without the HTML of the catalogue.
    public let summary: String
    public let description: String
    public let detailPage: URL?
    /// Large previews, in order.
    public let previews: [URL]
    /// A small preview for the grid.
    public let thumbnail: URL?
    public let downloads: Int
    /// 0 to 100; 50 means no votes either way.
    public let score: Int
    /// The score as pling.com shows it: 0.0 to 10.0.
    public var rating: Double { Double(score) / 10 }
    /// The licence named in the tags, such as "GPL-3.0"; nil when none is named.
    public let licence: String?
    /// When the theme was put on pling.com; "Newest" sorts by this.
    public let created: Date?
    /// When it was last changed (a new file, a new description).
    public let changed: Date?
    public let files: [File]
    /// The catalogue keeps this theme out of apps; it is only offered on the website.
    public let isExcludedFromApps: Bool

    /// Licence tags as pling uses them, and how to show them.
    static let licences: [(tag: String, name: String)] = [
        ("gplv3", "GPL-3.0"), ("gplv2", "GPL-2.0"), ("agplv3", "AGPL-3.0"),
        ("lgplv3", "LGPL-3.0"), ("lgplv2", "LGPL-2.1"), ("lgplv21", "LGPL-2.1"),
        ("mit-license", "MIT"), ("mit", "MIT"), ("apache-license", "Apache-2.0"),
        ("bsd-license", "BSD"), ("bsd", "BSD"), ("mpl", "MPL-2.0"),
        ("cc0", "CC0"), ("cc-by", "CC BY"), ("cc-by-sa", "CC BY-SA"), ("cc-by-nc", "CC BY-NC"),
        ("cc-by-nc-sa", "CC BY-NC-SA"), ("cc-by-nd", "CC BY-ND"), ("cc-by-nc-nd", "CC BY-NC-ND"),
        ("public-domain", "Public Domain"), ("artistic-license", "Artistic-2.0"),
    ]

    init?(entry: [String: Any]) {
        guard let id = PlingCatalog.integer(entry["id"]), id > 0,
              let name = PlingCatalog.string(entry["name"]) else { return nil }
        self.id = id
        self.name = PlainText.from(html: name)
        author = PlingCatalog.string(entry["personid"]) ?? String(localized: "Unknown")
        summary = PlainText.from(html: PlingCatalog.string(entry["summary"]) ?? "")
        description = PlainText.from(html: PlingCatalog.string(entry["description"]) ?? "")
        detailPage = PlingCatalog.secureURL(entry["detailpage"])
        previews = (1...9).compactMap { PlingCatalog.secureURL(entry["previewpic\($0)"]) }
        thumbnail = (PlingCatalog.secureURL(entry["smallpreviewpic1"]) ?? previews.first).map(Self.smallVersion)
        downloads = max(0, PlingCatalog.integer(entry["downloads"]) ?? 0)
        score = min(100, max(0, PlingCatalog.integer(entry["score"]) ?? 50))
        let tags = Set((PlingCatalog.string(entry["tags"]) ?? "").lowercased().split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) })
        licence = Self.licences.first { tags.contains($0.tag) }?.name
        created = PlingCatalog.string(entry["created"]).flatMap { try? Date($0, strategy: .iso8601) }
        changed = PlingCatalog.string(entry["changed"]).flatMap { try? Date($0, strategy: .iso8601) }
        isExcludedFromApps = (PlingCatalog.integer(entry["ghns_excluded"]) ?? 0) != 0
        files = (1...20).compactMap { number in
            guard let url = PlingCatalog.secureURL(entry["downloadlink\(number)"]) else { return nil }
            let name = File.safeName(PlingCatalog.string(entry["downloadname\(number)"]) ?? url.lastPathComponent)
            let kilobytes = PlingCatalog.integer(entry["downloadsize\(number)"])
            let md5 = PlingCatalog.string(entry["downloadmd5sum\(number)"])?.lowercased()
            let isMD5 = md5.map { $0.count == 32 && $0.allSatisfy(\.isHexDigit) } ?? false
            return File(id: number, name: name, url: url, size: kilobytes.flatMap { $0 > 0 ? $0 * 1024 : nil },
                        md5: isMD5 ? md5 : nil)
        }
    }

    /// The catalogue's image cache serves smaller sizes under another path: 280 × 171
    /// instead of 770 × 540, a quarter of the bytes.
    static func smallVersion(of url: URL) -> URL {
        guard url.host == "images.pling.com", url.path.hasPrefix("/cache/") else { return url }
        var parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count > 2 else { return url }
        parts[1] = "280x171"
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = "/" + parts.joined(separator: "/")
        return components?.url ?? url
    }
}

extension PlingTheme {
    /// The newer version of an installed file: the file of the same name when its checksum
    /// changed. A file under a new name (authors often put the version in it) counts only
    /// when it is the theme's single candidate; with several variants, which one replaced
    /// the installed one can't be told. Without a checksum from the install, nothing can be
    /// told either.
    public func updatedFile(installedName: String?, installedMD5: String?, among candidates: [File]) -> File? {
        guard let installedMD5 else { return nil }
        if let installedName, let sameName = candidates.first(where: { $0.name == installedName }) {
            return sameName.md5.map { $0 != installedMD5 } == true ? sameName : nil
        }
        guard candidates.count == 1, let only = candidates.first, let md5 = only.md5, md5 != installedMD5 else {
            return nil
        }
        return only
    }
}

extension PlingTheme.File {
    /// A file name that is safe to create: the last path part only, without control
    /// characters, not hidden, not empty.
    static func safeName(_ name: String) -> String {
        let last = name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        var cleaned = String(last.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != ":" })
        while cleaned.hasPrefix(".") || cleaned.hasPrefix("~") { cleaned.removeFirst() }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "download" : String(cleaned.prefix(200))
    }
}

/// HTML from the catalogue as plain text: tags removed, line breaks kept, entities decoded.
enum PlainText {
    static func from(html: String) -> String {
        var text = html.replacingOccurrences(of: "\r\n", with: "\n")
        // Line breaks the HTML makes, before the tags go.
        text = text.replacingOccurrences(of: #"<\s*br\s*/?\s*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<\s*/\s*(p|div|li|h[1-6])\s*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<\s*li[^>]*>"#, with: "• ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        text = decodeEntities(text)
        text = text.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
                                "#39": "'", "hellip": "…", "ndash": "–", "mdash": "—"]

    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = Substring(text)
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            let afterAmpersand = rest.index(after: ampersand)
            guard let semicolon = rest[afterAmpersand...].prefix(10).firstIndex(of: ";") else {
                result += "&"
                rest = rest[afterAmpersand...]
                continue
            }
            let entity = String(rest[afterAmpersand..<semicolon])
            if let replacement = named[entity.lowercased()] ?? numericEntity(entity) {
                result += replacement
            } else {
                result += rest[ampersand...semicolon]
            }
            rest = rest[rest.index(after: semicolon)...]
        }
        return result + rest
    }

    private static func numericEntity(_ entity: String) -> String? {
        guard entity.hasPrefix("#") else { return nil }
        let digits = entity.dropFirst()
        let value = digits.lowercased().hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
        guard let value, let scalar = Unicode.Scalar(value), value >= 32 else { return nil }
        return String(Character(scalar))
    }
}
