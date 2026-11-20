import Foundation

/// Where a cape was downloaded from, stored in the cape itself (the optional `Source`
/// dictionary), so that it travels with the file: the page to credit and visit, and the
/// downloaded file's name and checksum, to notice when the author uploads a new version.
///
/// The original Mousecape ignores the key and its editor drops it on save. The values come
/// from a file, so they are untrusted: the page must be an HTTPS link, the checksum hex.
public struct CapeSource: Equatable, Sendable {
    /// The catalogue, such as `pling.com`.
    public var site: String
    /// The theme's id in that catalogue.
    public var themeID: Int
    public var page: URL?
    /// The downloaded file's name.
    public var fileName: String?
    /// The downloaded file's MD5, lower-case hex.
    public var md5: String?

    public static let plingSite = "pling.com"

    public init(site: String, themeID: Int, page: URL? = nil, fileName: String? = nil, md5: String? = nil) {
        self.site = site
        self.themeID = themeID
        self.page = page
        self.fileName = fileName
        self.md5 = md5
    }

    /// A theme from the pling.com catalogue and the file it was installed from.
    public init(theme: PlingTheme, file: PlingTheme.File) {
        self.init(site: Self.plingSite, themeID: theme.id, page: theme.detailPage, fileName: file.name, md5: file.md5)
    }

    init?(propertyList value: Any?) {
        guard let dict = value as? [String: Any], let site = dict[Key.site] as? String, !site.isEmpty,
              let themeID = PlingCatalog.integer(dict[Key.themeID]), themeID > 0 else { return nil }
        self.site = site
        self.themeID = themeID
        page = PlingCatalog.secureURL(dict[Key.page])
        fileName = (dict[Key.file] as? String).map(PlingTheme.File.safeName)
        let md5 = (dict[Key.md5] as? String)?.lowercased()
        self.md5 = md5.flatMap { $0.count == 32 && $0.allSatisfy(\.isHexDigit) ? $0 : nil }
    }

    var propertyList: [String: Any] {
        var dict: [String: Any] = [Key.site: site, Key.themeID: themeID]
        dict[Key.page] = page?.absoluteString
        dict[Key.file] = fileName
        dict[Key.md5] = md5
        return dict
    }

    enum Key {
        static let site = "Site"
        static let themeID = "ID"
        static let page = "Page"
        static let file = "File"
        static let md5 = "MD5"
    }
}
