import Foundation

/// A MaCursor theme (`.cursor`). Its format grew out of Mousecape's: the file is a cape
/// under other names: `ThemeName`, `Creator` and `ThemeVersion` instead of `CapeName`,
/// `Author` and `CapeVersion`, plus a `UUID`. Its cursors have the same keys as a cape's,
/// with one sprite sheet per scale. Written from the files MaCursor ships; no code from it
/// (it is GPL-3.0).
public struct MaCursorTheme: CursorThemeConvertible {
    public var name: String
    /// The theme's `Creator`; empty if it has none.
    public var creator: String
    public var version: Double
    public var cursors: [CapeCursor]
    /// Cursors that couldn't be read, by identifier.
    public var skipped: [String]

    public static let fileExtension = "cursor"

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url), fallbackName: url.deletingPathExtension().lastPathComponent)
    }

    /// `fallbackName` names a theme without a `ThemeName` (usually the file name).
    public init(data: Data, fallbackName: String = "") throws {
        guard let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entries = dict["Cursors"] as? [String: Any] else { throw MaCursorError.notATheme }
        name = (dict["ThemeName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
        creator = dict["Creator"] as? String ?? ""
        version = (dict["ThemeVersion"] as? NSNumber)?.doubleValue ?? 1
        var cursors: [CapeCursor] = []
        var skipped: [String] = []
        for (identifier, value) in entries {
            // Identifiers become file names in exports, as in a cape.
            guard Cape.isValidIdentifier(identifier), let entry = value as? [String: Any],
                  let cursor = try? CapeCursor(identifier: identifier, propertyList: entry) else {
                skipped.append(identifier)
                continue
            }
            cursors.append(cursor)
        }
        guard !cursors.isEmpty else { throw MaCursorError.noCursorsFound }
        self.cursors = cursors
        self.skipped = skipped.sorted()
    }

    /// `author` stands in when the theme names no creator.
    public func makeCape(author: String) throws -> (cape: Cape, skipped: [String]) {
        var cape = Cape.converted(kind: "macursor", name: name, author: creator.isEmpty ? author : creator,
                                  cursors: cursors)
        cape.version = version
        return (cape, skipped)
    }
}

public enum MaCursorError: Error, Equatable, LocalizedError {
    case notATheme
    case noCursorsFound

    public var errorDescription: String? {
        switch self {
        case .notATheme: String(localized: "The file is not a MaCursor theme.")
        case .noCursorsFound: String(localized: "The MaCursor theme has no cursors Mousecape can read.")
        }
    }
}
