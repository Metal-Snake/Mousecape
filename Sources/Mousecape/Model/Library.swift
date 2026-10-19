import Foundation
import Observation
import CapeKit

/// The capes in ~/Library/Application Support/Mousecape/capes (the same folder the original
/// app used), one `<identifier>.cape` file each.
@MainActor @Observable
final class Library {
    private(set) var capes: [Cape] = []
    private(set) var appliedIdentifier: String?
    /// Per cape, the cursors with problems (see `CursorProblem`); capes without any are absent.
    private(set) var problems: [Cape.ID: [String: [CursorProblem]]] = [:]
    /// Files in the folder that could not be read, shown so they don't vanish silently.
    private(set) var unreadable: [URL] = []
    /// Files whose cape has the same identifier as one already in the library.
    private(set) var duplicates: [URL] = []
    /// Capes edited since they came into the library: their original can be restored.
    private(set) var editedIdentifiers: Set<String> = []

    let folder: URL
    /// The unchanged file of each edited cape, `<identifier>.cape`, kept from before its
    /// first save in the editor.
    let originalsFolder: URL
    /// Moves a file to the Trash (tests swap it for plain removal).
    @ObservationIgnored var moveToTrash: (URL) throws -> Void = {
        try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
    }

    /// `originalsFolder` defaults to `Originals` next to the library folder, outside it so
    /// the original Mousecape and the agent never see the copies.
    init(folder: URL = Library.defaultFolder, originalsFolder: URL? = nil) {
        self.folder = folder
        self.originalsFolder = originalsFolder
            ?? folder.deletingLastPathComponent().appending(path: "Originals", directoryHint: .isDirectory)
        reload()
    }

    /// `MOUSECAPE_LIBRARY` points the app at another folder (for testing).
    static var defaultFolder: URL {
        if let override = ProcessInfo.processInfo.environment["MOUSECAPE_LIBRARY"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL.applicationSupportDirectory.appending(path: "Mousecape/capes", directoryHint: .isDirectory)
    }

    var appliedCape: Cape? { capes.first { $0.identifier == appliedIdentifier } }

    /// Names, sizes and dates of the files at the last reload.
    private var fingerprint: [String] = []

    /// Cheap check used when the app comes to the front: reads the capes again only if the
    /// folder changed (e.g. in Finder); the applied cape is always refreshed.
    func reloadIfChanged() {
        if currentFingerprint() != fingerprint {
            reload()
        } else {
            appliedIdentifier = EnginePreferences.appliedCapeIdentifier
        }
    }

    private func currentFingerprint() -> [String] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)) ?? []
        return files.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return "\(url.lastPathComponent)|\(values?.fileSize ?? -1)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }.sorted()
    }

    /// Reads every cape in the folder. Each cape belongs in `<identifier>.cape`, because
    /// that is where the agent looks for the applied one at login: a cape under another
    /// name is renamed when that name is free, and counts as a duplicate when it isn't.
    func reload() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        var parsed: [Cape] = []
        var failed: [URL] = []
        for url in files where url.pathExtension.lowercased() == "cape" {
            if let cape = try? Cape(contentsOf: url) {
                parsed.append(cape)
            } else {
                failed.append(url)
            }
        }

        var byIdentifier: [String: Cape] = [:]
        var extra: [URL] = []
        // Files already named after their identifier first, so they win over stray copies.
        let ordered = parsed.sorted { a, b in
            let aCanonical = a.fileURL?.lastPathComponent == fileURL(for: a.identifier).lastPathComponent
            let bCanonical = b.fileURL?.lastPathComponent == fileURL(for: b.identifier).lastPathComponent
            if aCanonical != bCanonical { return aCanonical }
            return (a.fileURL?.lastPathComponent ?? "") < (b.fileURL?.lastPathComponent ?? "")
        }
        for var cape in ordered {
            if byIdentifier[cape.identifier] != nil {
                if let url = cape.fileURL { extra.append(url) }
                continue
            }
            let canonical = fileURL(for: cape.identifier)
            if let url = cape.fileURL, url.lastPathComponent != canonical.lastPathComponent,
               !cape.identifier.contains("/"), !FileManager.default.fileExists(atPath: canonical.path),
               (try? FileManager.default.moveItem(at: url, to: canonical)) != nil {
                cape.fileURL = canonical
            }
            byIdentifier[cape.identifier] = cape
        }
        fingerprint = currentFingerprint()

        capes = byIdentifier.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        unreadable = failed
        duplicates = extra.sorted { $0.lastPathComponent < $1.lastPathComponent }
        problems = Dictionary(uniqueKeysWithValues: capes.compactMap { cape in
            let found = cape.problems
            return found.isEmpty ? nil : (cape.id, found)
        })
        appliedIdentifier = EnginePreferences.appliedCapeIdentifier
        editedIdentifiers = Set(capes.map(\.identifier).filter {
            FileManager.default.fileExists(atPath: originalURL(for: $0).path)
        })
    }

    // MARK: - Applying

    func apply(_ cape: Cape) throws {
        guard let url = cape.fileURL else { throw LibraryError.notInLibrary }
        let succeeded = Engine.apply(url)
        // The engine skips cursors it cannot register; the cape still counts as applied.
        appliedIdentifier = EnginePreferences.appliedCapeIdentifier
        guard succeeded else {
            if appliedIdentifier == cape.identifier { throw LibraryError.partiallyApplied(cape.name) }
            throw LibraryError.applyFailed(cape.name)
        }
    }

    /// Throws when some cursors kept the cape's look (the engine logs which).
    func resetToDefault() throws {
        let succeeded = Engine.reset()
        appliedIdentifier = nil
        if !succeeded { throw LibraryError.resetIncomplete }
    }

    /// Applies the current setup again, e.g. after the left-handed setting changed: the
    /// applied cape, or else the macOS cursors (mirrored in left-handed mode).
    func reapply() throws {
        if let cape = appliedCape {
            try apply(cape)
        } else {
            try resetToDefault()
        }
    }

    // MARK: - Adding and removing

    /// The library cape a file would replace, if its identifier is already taken.
    func existingCape(forFileAt url: URL) throws -> Cape? {
        let cape = try Cape(contentsOf: url)
        return capes.first { $0.identifier == cape.identifier }
    }

    /// Copies a `.cape` file into the library (replacing a cape with the same identifier,
    /// and with it the original of an edited one: the import is the new starting point).
    @discardableResult
    func importCape(at url: URL) throws -> Cape {
        let cape = try Cape(contentsOf: url)
        discardOriginal(for: cape.identifier)
        let destination = fileURL(for: cape.identifier)
        if url.standardizedFileURL != destination.standardizedFileURL {
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: copyToTemporary(url))
            } else {
                try FileManager.default.copyItem(at: url, to: destination)
            }
        }
        reload()
        return capes.first { $0.identifier == cape.identifier } ?? cape
    }

    /// Writes a cape built in memory (MightyMouse conversion, cursor dump) into the library.
    @discardableResult
    func add(propertyList: [String: Any]) throws -> Cape {
        var cape = try Cape(propertyList: propertyList)
        while capes.contains(where: { $0.identifier == cape.identifier }) {
            cape.identifier += ".\(UUID().uuidString.prefix(8))"
        }
        discardOriginal(for: cape.identifier)
        try cape.propertyListData().write(to: fileURL(for: cape.identifier), options: .atomic)
        reload()
        return capes.first { $0.identifier == cape.identifier } ?? cape
    }

    /// Writes a cape converted on import over the one with the same identifier (a theme
    /// imported again); an applied cape is applied again. Like any import, it starts over:
    /// the original of an edited cape goes.
    @discardableResult
    func replace(with cape: Cape) throws -> Cape {
        discardOriginal(for: cape.identifier)
        try cape.propertyListData().write(to: fileURL(for: cape.identifier), options: .atomic)
        reload()
        let result = capes.first { $0.identifier == cape.identifier } ?? cape
        if cape.identifier == appliedIdentifier { try apply(result) }
        return result
    }

    /// Writes an edited (or new) cape. Before an existing cape's first save, its unchanged
    /// file is kept in `originalsFolder`; later saves leave that copy alone, and a save that
    /// brings the cape back to it removes it. When the identifier changed, the original
    /// follows and the old file goes to the Trash. An applied cape is applied again so the
    /// screen shows the saved version.
    @discardableResult
    func save(_ cape: Cape, originalIdentifier: String?) throws -> Cape {
        let identifier = cape.identifier.trimmingCharacters(in: .whitespaces)
        guard !identifier.isEmpty, !identifier.contains("/"), !identifier.hasPrefix(".") else {
            throw LibraryError.invalidIdentifier
        }
        if identifier != originalIdentifier, capes.contains(where: { $0.identifier == identifier }) {
            throw LibraryError.identifierTaken(identifier)
        }
        var saved = cape
        saved.identifier = identifier
        let destination = fileURL(for: identifier)
        let existing = originalIdentifier.flatMap { id in capes.first { $0.identifier == id } }

        if let existing, let source = existing.fileURL {
            let original = originalURL(for: existing.identifier)
            if !FileManager.default.fileExists(atPath: original.path) {
                try FileManager.default.createDirectory(at: originalsFolder, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: original)
            }
            if identifier != existing.identifier {
                discardOriginal(for: identifier)
                try FileManager.default.moveItem(at: original, to: originalURL(for: identifier))
            }
        } else {
            discardOriginal(for: identifier)                    // a new cape starts fresh
        }
        let data = try saved.propertyListData()
        try data.write(to: destination, options: .atomic)
        // Saved back to how it was imported: nothing to restore.
        if existing != nil, let original = try? Cape(contentsOf: originalURL(for: identifier)),
           (try? original.propertyListData()) == data {
            try? FileManager.default.removeItem(at: originalURL(for: identifier))
        }

        let wasApplied = originalIdentifier != nil && originalIdentifier == appliedIdentifier
        // The file the cape came from goes to the Trash when it was a different one: after
        // a new identifier, or when it wasn't named after its identifier.
        if let previous = cape.fileURL, previous.standardizedFileURL != destination.standardizedFileURL,
           FileManager.default.fileExists(atPath: previous.path) {
            try? moveToTrash(previous)
        }
        reload()
        let result = capes.first { $0.identifier == identifier } ?? saved
        if wasApplied { try apply(result) }
        return result
    }

    /// A copy under a new identifier, saved next to the original.
    @discardableResult
    func duplicate(_ cape: Cape) throws -> Cape {
        var copy = cape
        copy.identifier = cape.identifier + ".copy.\(Int(Date().timeIntervalSince1970))"
        copy.name = String(localized: "\(cape.name) Copy")
        copy.fileURL = nil
        return try save(copy, originalIdentifier: nil)
    }

    /// Moves the cape file (and the original of an edited cape) to the Trash; resets the
    /// cursors first if it is applied.
    func delete(_ cape: Cape) throws {
        if cape.identifier == appliedIdentifier { try resetToDefault() }
        if let url = cape.fileURL {
            try moveToTrash(url)
        }
        discardOriginal(for: cape.identifier)
        reload()
    }

    /// Brings an edited cape back to how it came into the library. The edited version goes
    /// to the Trash; an applied cape is applied again.
    @discardableResult
    func revertToOriginal(_ cape: Cape) throws -> Cape {
        let originalFile = originalURL(for: cape.identifier)
        guard FileManager.default.fileExists(atPath: originalFile.path) else { throw LibraryError.noOriginal(cape.name) }
        let original = try Cape(contentsOf: originalFile)
        // Edits may have changed the identifier; the original brings the old one back.
        if original.identifier != cape.identifier, capes.contains(where: { $0.identifier == original.identifier }) {
            throw LibraryError.identifierTaken(original.identifier)
        }
        let wasApplied = cape.identifier == appliedIdentifier
        if let current = cape.fileURL, FileManager.default.fileExists(atPath: current.path) {
            try moveToTrash(current)
        }
        try FileManager.default.moveItem(at: originalFile, to: fileURL(for: original.identifier))
        reload()
        let reverted = capes.first { $0.identifier == original.identifier } ?? original
        if wasApplied { try apply(reverted) }
        return reverted
    }

    /// Captures the cursors currently on screen as a new cape.
    @discardableResult
    func captureCurrentCursors() throws -> Cape {
        let temporary = FileManager.default.temporaryDirectory
            .appending(path: "Mousecape Dump \(Int(Date().timeIntervalSince1970)).cape")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard Engine.dumpCurrentCursors(to: temporary) else { throw LibraryError.dumpFailed }
        let cape = try Cape(contentsOf: temporary)
        return try add(propertyList: cape.propertyList)
    }

    // MARK: - Private

    private func fileURL(for identifier: String) -> URL {
        folder.appending(path: identifier + ".cape")
    }

    private func originalURL(for identifier: String) -> URL {
        originalsFolder.appending(path: identifier + ".cape")
    }

    /// Moves an original that no longer belongs to the cape under `identifier` (it was
    /// replaced, deleted or never edited) to the Trash.
    private func discardOriginal(for identifier: String) {
        let url = originalURL(for: identifier)
        if FileManager.default.fileExists(atPath: url.path) { try? moveToTrash(url) }
    }

    private func copyToTemporary(_ url: URL) throws -> URL {
        let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".cape")
        try FileManager.default.copyItem(at: url, to: temporary)
        return temporary
    }
}

enum LibraryError: LocalizedError {
    case notInLibrary
    case applyFailed(String)
    case partiallyApplied(String)
    case dumpFailed
    case conversionFailed
    case invalidIdentifier
    case resetIncomplete
    case identifierTaken(String)
    case noOriginal(String)

    var errorDescription: String? {
        switch self {
        case .resetIncomplete:
            String(localized: "Some cursors could not be reset and still show the previous cape. Logging out and back in restores them.")
        case .invalidIdentifier:
            String(localized: "The identifier must not be empty, contain “/” or start with a dot.")
        case .identifierTaken(let identifier):
            String(localized: "Another cape in the library already uses the identifier “\(identifier)”.")
        case .notInLibrary: String(localized: "The cape is not saved in the library.")
        case .noOriginal(let name): String(localized: "There is no original of “\(name)” to go back to.")
        case .applyFailed(let name): String(localized: "“\(name)” could not be applied.")
        case .partiallyApplied(let name):
            String(localized: "“\(name)” is applied, but some of its cursors were rejected by macOS. Check them in the editor.")
        case .dumpFailed: String(localized: "The current cursors could not be captured.")
        case .conversionFailed: String(localized: "The MightyMouse file could not be converted.")
        }
    }
}
