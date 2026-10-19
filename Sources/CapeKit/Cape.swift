import Foundation

/// A cursor theme as stored in a `.cape` file: an XML property list holding metadata and,
/// per system cursor identifier, its frames at one or more pixel densities.
public struct Cape: Identifiable, Equatable, Sendable {
    public var identifier: String
    public var name: String
    public var author: String
    public var version: Double
    public var isHiDPI: Bool
    /// Sorted for display: the main pointers first, then by name.
    public var cursors: [CapeCursor]
    /// Where the cape was loaded from, if it came from a file.
    public var fileURL: URL?
    /// Keys of the file this version doesn't know; written back unchanged.
    public var otherKeys: OtherKeys = .none

    public var id: String { identifier }

    /// The cape format this code reads and writes (`Version`/`MinimumVersion` keys).
    public static let formatVersion = 2.0

    public init(identifier: String, name: String, author: String, version: Double = 1.0,
                isHiDPI: Bool = true, cursors: [CapeCursor] = [], fileURL: URL? = nil) {
        self.identifier = identifier
        self.name = name
        self.author = author
        self.version = version
        self.isHiDPI = isHiDPI
        self.cursors = cursors.sorted(by: CapeCursor.displayOrder)
        self.fileURL = fileURL
    }

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        try self.init(propertyListData: data, fileURL: url)
    }

    public init(propertyListData data: Data, fileURL: URL? = nil) throws {
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = plist as? [String: Any] else { throw CapeError.notACape }
        try self.init(propertyList: dict, fileURL: fileURL)
    }

    public init(propertyList dict: [String: Any], fileURL: URL? = nil) throws {
        let minimum = (dict[Key.minimumVersion] as? NSNumber)?.doubleValue ?? 0
        guard minimum <= Self.formatVersion else { throw CapeError.unsupportedVersion(minimum) }
        guard let identifier = dict[Key.identifier] as? String,
              let cursors = dict[Key.cursors] as? [String: Any] else { throw CapeError.notACape }

        var parsed: [CapeCursor] = []
        for (cursorID, value) in cursors {
            guard let cursorDict = value as? [String: Any] else { throw CapeError.invalidCursor(cursorID) }
            parsed.append(try CapeCursor(identifier: cursorID, propertyList: cursorDict))
        }
        self.init(identifier: identifier,
                  name: dict[Key.name] as? String ?? identifier,
                  author: dict[Key.author] as? String ?? "",
                  version: (dict[Key.capeVersion] as? NSNumber)?.doubleValue ?? 1.0,
                  isHiDPI: (dict[Key.hiDPI] as? NSNumber)?.boolValue ?? false,
                  cursors: parsed,
                  fileURL: fileURL)
        otherKeys = OtherKeys(dict, known: Key.all)
    }

    /// The property list as written to a `.cape` file.
    public var propertyList: [String: Any] {
        otherKeys.merged(with: [
            Key.version: Self.formatVersion,
            Key.minimumVersion: Self.formatVersion,
            Key.identifier: identifier,
            Key.name: name,
            Key.author: author,
            Key.capeVersion: version,
            Key.hiDPI: isHiDPI,
            Key.cloud: false,
            Key.cursors: Dictionary(uniqueKeysWithValues: cursors.map { ($0.identifier, $0.propertyList) }),
        ])
    }

    public func propertyListData() throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0)
    }

    enum Key {
        static let version = "Version"
        static let minimumVersion = "MinimumVersion"
        static let identifier = "Identifier"
        static let name = "CapeName"
        static let author = "Author"
        static let capeVersion = "CapeVersion"
        static let hiDPI = "HiDPI"
        static let cloud = "Cloud"
        static let cursors = "Cursors"
        static let all: Set<String> = [version, minimumVersion, identifier, name, author, capeVersion,
                                       hiDPI, cloud, cursors]
    }
}

public enum CapeError: Error, Equatable, LocalizedError {
    case notACape
    case unsupportedVersion(Double)
    case invalidCursor(String)

    public var errorDescription: String? {
        switch self {
        case .notACape: "The file is not a valid cape."
        case .unsupportedVersion(let v): "The cape needs a newer Mousecape (format \(v))."
        case .invalidCursor(let id): "The cursor \(id) in the cape is damaged."
        }
    }
}
