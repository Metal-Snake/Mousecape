import Foundation
import CapeKit

/// One stored state of a cape.
struct CapeVersion: Identifiable, Hashable {
    enum Kind: Hashable {
        /// How the cape came into the library (imported, or found there at first start).
        case original
        /// A state a later save replaced.
        case saved
    }

    let url: URL
    let kind: Kind
    /// When this state was written.
    let date: Date

    var id: URL { url }
}

/// The versions of each cape in the library, kept in `<folder>/<identifier>/`:
/// `original.cape` (the state the cape came into the library with) and one dated file per
/// state a save replaced. The current state is the library file itself.
struct CapeHistory {
    let folder: URL
    /// Saved states kept per cape; older ones go to the Trash.
    static let savedLimit = 20

    var moveToTrash: (URL) throws -> Void

    private static let originalName = "original.cape"

    /// `<folder>/<identifier>`. Never outside `folder`: identifiers come from cape files, and
    /// this folder gets moved to the Trash, so an identifier like `../capes` must not reach
    /// here (they're refused when a cape is read; this is the second line).
    func capeFolder(for identifier: String) throws -> URL {
        guard Cape.isValidIdentifier(identifier) else { throw CapeError.invalidIdentifier(identifier) }
        return folder.appending(path: identifier, directoryHint: .isDirectory)
    }

    func originalURL(for identifier: String) throws -> URL {
        try capeFolder(for: identifier).appending(path: Self.originalName)
    }

    /// The original first, then the saved states from oldest to newest.
    func versions(for identifier: String) -> [CapeVersion] {
        guard let capeFolder = try? capeFolder(for: identifier) else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: capeFolder, includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles)) ?? []
        let versions = files.filter { $0.pathExtension == "cape" }.map { url in
            CapeVersion(url: url, kind: url.lastPathComponent == Self.originalName ? .original : .saved,
                        date: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast)
        }
        return versions.sorted { a, b in
            if a.kind != b.kind { return a.kind == .original }
            if a.date != b.date { return a.date < b.date }
            return a.url.lastPathComponent < b.url.lastPathComponent
        }
    }

    /// Keeps `file` as the original when there is none yet.
    func ensureOriginal(for identifier: String, from file: URL) throws {
        let original = try originalURL(for: identifier)
        guard !FileManager.default.fileExists(atPath: original.path) else { return }
        try FileManager.default.createDirectory(at: capeFolder(for: identifier), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: file, to: original)
    }

    /// Whether `file` differs from the original (false when there is no original).
    func differsFromOriginal(_ file: URL, identifier: String) -> Bool {
        guard let original = try? originalURL(for: identifier),
              FileManager.default.fileExists(atPath: original.path) else { return false }
        return !Self.sameContents(file, original)
    }

    /// Keeps `file` (the state a save is about to replace) as a saved version, unless it
    /// equals the original or the newest saved version. Drops the oldest beyond the limit.
    func record(_ file: URL, for identifier: String) throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let existing = versions(for: identifier)
        if existing.contains(where: { $0.kind == .original && Self.sameContents($0.url, file) }) { return }
        if let newest = existing.last(where: { $0.kind == .saved }), Self.sameContents(newest.url, file) { return }
        let capeFolder = try capeFolder(for: identifier)
        try FileManager.default.createDirectory(at: capeFolder, withIntermediateDirectories: true)
        // Local time, so the names match what Finder shows.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let stamp = formatter.string(from: Date())
        var destination = capeFolder.appending(path: "\(stamp).cape")
        var number = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = capeFolder.appending(path: "\(stamp) \(number).cape")
            number += 1
        }
        try FileManager.default.copyItem(at: file, to: destination)
        // Over the limit, the oldest go; failing that only leaves one too many.
        let saved = versions(for: identifier).filter { $0.kind == .saved }
        for old in saved.dropLast(Self.savedLimit) { try? moveToTrash(old.url) }
    }

    /// Moves the saved states (not the original) to the Trash.
    func removeSavedVersions(for identifier: String) throws {
        for version in versions(for: identifier) where version.kind == .saved { try moveToTrash(version.url) }
    }

    /// Moves a cape's whole history to the Trash (deleted, or imported again).
    func discard(for identifier: String) throws {
        let url = try capeFolder(for: identifier)
        if FileManager.default.fileExists(atPath: url.path) { try moveToTrash(url) }
    }

    /// Moves the history along with an identifier change.
    func rename(from old: String, to new: String) throws {
        let source = try capeFolder(for: old), destination = try capeFolder(for: new)
        guard old != new, FileManager.default.fileExists(atPath: source.path) else { return }
        try discard(for: new)
        try FileManager.default.moveItem(at: source, to: destination)
    }

    static func sameContents(_ a: URL, _ b: URL) -> Bool {
        let sizeA = (try? a.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        let sizeB = (try? b.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        guard sizeA == sizeB else { return false }
        return (try? Data(contentsOf: a)) == (try? Data(contentsOf: b))
    }
}
