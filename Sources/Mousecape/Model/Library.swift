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
    /// Capes that differ from how they came into the library.
    private(set) var editedIdentifiers: Set<String> = []

    let folder: URL
    /// Each cape's original and earlier states (see `CapeHistory`).
    let versionsFolder: URL
    /// Moves a file to the Trash and returns where it went (tests swap in a folder of
    /// their own).
    @ObservationIgnored var moveToTrash: (URL) throws -> URL? = { url in
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        return trashed as URL?
    }

    var history: CapeHistory { CapeHistory(folder: versionsFolder, moveToTrash: moveToTrash) }

    /// `versionsFolder` defaults to `Versions` next to the library folder, outside it so
    /// the original Mousecape and the agent never see the copies.
    init(folder: URL = Library.defaultFolder, versionsFolder: URL? = nil) {
        self.folder = folder
        self.versionsFolder = versionsFolder
            ?? folder.deletingLastPathComponent().appending(path: "Versions", directoryHint: .isDirectory)
        reload()
    }

    // MARK: - Installed from the gallery

    /// The cape in the library that a pling.com theme was installed as (its `Source`); nil
    /// when it was never installed, or the cape has been deleted since.
    func cape(installedFromGalleryTheme id: Int) -> Cape? {
        capes.first { $0.source?.site == CapeSource.plingSite && $0.source?.themeID == id }
    }

    /// Every cape installed from a pling.com theme: a theme can come in several versions.
    func capes(installedFromGalleryTheme id: Int) -> [Cape] {
        capes.filter { $0.source?.site == CapeSource.plingSite && $0.source?.themeID == id }
    }

    /// The pling.com themes that capes in the library came from.
    var installedGalleryThemes: [Int] {
        Array(Set(capes.compactMap { $0.source?.site == CapeSource.plingSite ? $0.source?.themeID : nil })).sorted()
    }

    /// Records a newer source file for a cape whose cursors it doesn't change ("Mark as Up
    /// to Date"). The cape's original in the history gets the same change, so that a cape
    /// that wasn't edited doesn't count as edited for it; no history entry is added.
    @discardableResult
    func updateSource(of cape: Cape, to source: CapeSource) throws -> Cape {
        guard let file = cape.fileURL else { throw LibraryError.notInLibrary }
        let original = try history.originalURL(for: cape.identifier)
        for url in [file, original] where FileManager.default.fileExists(atPath: url.path) {
            var stored = try Cape(contentsOf: url)
            stored.source = source
            try stored.propertyListData().write(to: url, options: .atomic)
        }
        reload()
        return capes.first { $0.identifier == cape.identifier } ?? cape
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
        updateProblems()
        appliedIdentifier = EnginePreferences.appliedCapeIdentifier
        // Every cape keeps the state it came in with: capes from before the history existed
        // (or added in Finder) get theirs now.
        let history = history
        var edited: Set<String> = []
        for cape in capes {
            guard let file = cape.fileURL else { continue }
            do {
                try history.ensureOriginal(for: cape.identifier, from: file)
            } catch {
                NSLog("Mousecape: no original kept for %@: %@", cape.identifier, "\(error)")
            }
            if history.differsFromOriginal(file, identifier: cape.identifier) { edited.insert(cape.identifier) }
        }
        editedIdentifiers = edited
    }

    /// Per cape, the cursors with problems; in left-handed mode also uneven mirroring.
    func updateProblems() {
        let leftHanded = EnginePreferences.leftHanded
        problems = Dictionary(uniqueKeysWithValues: capes.compactMap { cape in
            let found = cape.problems(leftHanded: leftHanded)
            return found.isEmpty ? nil : (cape.id, found)
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

    /// Copies a `.cape` file into the library, replacing a cape with the same identifier.
    /// The import becomes the cape's original; the replaced states stay in its history.
    @discardableResult
    func importCape(at url: URL) throws -> Cape {
        let cape = try Cape(contentsOf: url)
        let destination = fileURL(for: cape.identifier)
        // Opening the library's own file (e.g. from Finder) replaces nothing.
        if url.standardizedFileURL != destination.standardizedFileURL {
            try prepareHistoryForImport(of: cape.identifier, at: destination)
            try place(url, at: destination)
            try history.setOriginal(for: cape.identifier, from: destination)
        }
        reload()
        return capes.first { $0.identifier == cape.identifier } ?? cape
    }

    /// Before an import writes `destination`: a cape that is there keeps its states in its
    /// history (first, so that nothing is overwritten when that fails); a history without a
    /// cape is left over and goes.
    private func prepareHistoryForImport(of identifier: String, at destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try history.keepStatesBeforeImport(for: identifier, current: destination)
        } else {
            try history.discard(for: identifier)
        }
    }

    /// Writes a cape built in memory (MightyMouse conversion, cursor dump) into the library.
    @discardableResult
    func add(propertyList: [String: Any]) throws -> Cape {
        var cape = try Cape(propertyList: propertyList)
        while capes.contains(where: { $0.identifier == cape.identifier }) {
            cape.identifier += ".\(UUID().uuidString.prefix(8))"
        }
        try history.discard(for: cape.identifier)
        try cape.propertyListData().write(to: fileURL(for: cape.identifier), options: .atomic)
        reload()
        return capes.first { $0.identifier == cape.identifier } ?? cape
    }

    /// Writes a cape converted on import over the one with the same identifier (a theme
    /// imported again); an applied cape is applied again. Like any import, it becomes the
    /// cape's original; the replaced states stay in its history.
    @discardableResult
    func replace(with cape: Cape) throws -> Cape {
        let destination = fileURL(for: cape.identifier)
        let data = try cape.propertyListData()
        try prepareHistoryForImport(of: cape.identifier, at: destination)
        try data.write(to: destination, options: .atomic)
        try history.setOriginal(for: cape.identifier, from: destination)
        reload()
        let result = capes.first { $0.identifier == cape.identifier } ?? cape
        if cape.identifier == appliedIdentifier { try apply(result) }
        return result
    }

    /// Writes an edited (or new) cape. The state it replaces is kept in the history; a cape
    /// saved back to its original state gets the original's file again, so it no longer
    /// counts as edited. When the identifier changed, the history follows and the old file
    /// goes to the Trash. An applied cape is applied again so the screen shows the saved
    /// version.
    @discardableResult
    func save(_ cape: Cape, originalIdentifier: String?) throws -> Cape {
        let identifier = cape.identifier.trimmingCharacters(in: .whitespaces)
        guard Cape.isValidIdentifier(identifier) else {
            throw LibraryError.invalidIdentifier
        }
        if identifier != originalIdentifier, capes.contains(where: { $0.identifier == identifier }) {
            throw LibraryError.identifierTaken(identifier)
        }
        var saved = cape
        saved.identifier = identifier
        let destination = fileURL(for: identifier)
        let existing = originalIdentifier.flatMap { id in capes.first { $0.identifier == id } }
        let history = history

        // The history first: when keeping the replaced state fails, nothing is overwritten.
        if let existing, let source = existing.fileURL {
            try history.ensureOriginal(for: existing.identifier, from: source)
            try history.record(source, for: existing.identifier)
            try history.rename(from: existing.identifier, to: identifier)
        } else {
            try history.discard(for: identifier)                // a new cape starts fresh
        }
        let data = try saved.propertyListData()
        let original = try history.originalURL(for: identifier)
        if existing != nil, let originalCape = try? Cape(contentsOf: original),
           (try? originalCape.propertyListData()) == data {
            // Back to how it came in: the original's own bytes, so it isn't "edited".
            try place(original, at: destination)
        } else {
            try data.write(to: destination, options: .atomic)
        }

        let wasApplied = originalIdentifier != nil && originalIdentifier == appliedIdentifier
        // The file the cape came from goes to the Trash when it was a different one: after
        // a new identifier, or when it wasn't named after its identifier.
        if let previous = cape.fileURL, previous.standardizedFileURL != destination.standardizedFileURL,
           FileManager.default.fileExists(atPath: previous.path) {
            _ = try? moveToTrash(previous)
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
        // The copy is the user's own: updates from the gallery go to the original.
        copy.source = nil
        return try save(copy, originalIdentifier: nil)
    }

    /// Moves the cape file and its history to the Trash; resets the cursors first if it is
    /// applied. The result says where they went, for `putBack`.
    @discardableResult
    func delete(_ cape: Cape) throws -> TrashedCape {
        let wasApplied = cape.identifier == appliedIdentifier
        if wasApplied { try resetToDefault() }
        var file: TrashedCape.Move?
        if let url = cape.fileURL, let trashed = try moveToTrash(url) {
            file = TrashedCape.Move(from: url, trashed: trashed)
        }
        let historyFolder = try history.capeFolder(for: cape.identifier)
        let trashedHistory = try history.discard(for: cape.identifier).map {
            TrashedCape.Move(from: historyFolder, trashed: $0)
        }
        reload()
        return TrashedCape(identifier: cape.identifier, name: cape.name, file: file, history: trashedHistory,
                           wasApplied: wasApplied)
    }

    /// Undoes `delete`: moves the cape file and its history back from the Trash. Refuses
    /// when the file is no longer in the Trash, or when a cape with the same identifier
    /// came into the library since; it never overwrites anything.
    @discardableResult
    func putBack(_ trashed: TrashedCape) throws -> Cape {
        let manager = FileManager.default
        guard let file = trashed.file, manager.fileExists(atPath: file.trashed.path) else {
            throw LibraryError.notInTrash(trashed.name)
        }
        guard !capes.contains(where: { $0.identifier == trashed.identifier }),
              !manager.fileExists(atPath: file.from.path) else {
            throw LibraryError.identifierTaken(trashed.identifier)
        }
        try manager.moveItem(at: file.trashed, to: file.from)
        // The history is a bonus: without it the cape is back, just without earlier states.
        if let history = trashed.history, manager.fileExists(atPath: history.trashed.path),
           !manager.fileExists(atPath: history.from.path) {
            try? manager.createDirectory(at: history.from.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? manager.moveItem(at: history.trashed, to: history.from)
        }
        reload()
        guard let cape = capes.first(where: { $0.identifier == trashed.identifier }) else {
            throw LibraryError.notInLibrary
        }
        return cape
    }

    /// The stored states of a cape: its original first, then saved states, oldest first.
    func versions(of cape: Cape) -> [CapeVersion] {
        history.versions(for: cape.identifier)
    }

    /// Makes a stored version the current state again. The current state is kept in the
    /// history first, so this can be undone; an applied cape is applied again.
    @discardableResult
    func restore(_ version: CapeVersion, of cape: Cape) throws -> Cape {
        let restored = try Cape(contentsOf: version.url)
        // Edits may have changed the identifier; the version brings its own back.
        if restored.identifier != cape.identifier, capes.contains(where: { $0.identifier == restored.identifier }) {
            throw LibraryError.identifierTaken(restored.identifier)
        }
        let history = history
        let wasApplied = cape.identifier == appliedIdentifier
        var versionURL = version.url
        if let current = cape.fileURL {
            try history.record(current, for: cape.identifier)
            if restored.identifier != cape.identifier {
                try history.rename(from: cape.identifier, to: restored.identifier)
                versionURL = try history.capeFolder(for: restored.identifier).appending(path: version.url.lastPathComponent)
                if FileManager.default.fileExists(atPath: current.path) { _ = try moveToTrash(current) }
            }
        }
        try place(versionURL, at: fileURL(for: restored.identifier))
        reload()
        let result = capes.first { $0.identifier == restored.identifier } ?? restored
        if wasApplied { try apply(result) }
        return result
    }

    /// Brings a cape back to how it came into the library (see `restore`).
    @discardableResult
    func revertToOriginal(_ cape: Cape) throws -> Cape {
        guard let original = versions(of: cape).first(where: { $0.kind == .original }) else {
            throw LibraryError.noOriginal(cape.name)
        }
        return try restore(original, of: cape)
    }

    /// Moves a cape's saved states to the Trash, keeping its original and current state.
    func removeSavedVersions(of cape: Cape) throws {
        try history.removeSavedVersions(for: cape.identifier)
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

    /// Puts a copy of `source` at `destination`, replacing what's there in one step.
    private func place(_ source: URL, at destination: URL) throws {
        let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".cape")
        try FileManager.default.copyItem(at: source, to: temporary)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }
}

/// A cape `Library.delete` moved to the Trash, and where its files went, so that Undo can
/// put them back.
struct TrashedCape {
    struct Move {
        let from: URL
        let trashed: URL
    }

    let identifier: String
    let name: String
    let file: Move?
    let history: Move?
    /// Undo applies it again.
    let wasApplied: Bool
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
    case notInTrash(String)

    var errorDescription: String? {
        switch self {
        case .resetIncomplete:
            String(localized: "Some cursors could not be reset and still show the previous cape. Logging out and back in restores them.")
        case .invalidIdentifier:
            String(localized: "The identifier must not be empty, contain “/” or “:”, or start with a dot or tilde.")
        case .identifierTaken(let identifier):
            String(localized: "Another cape in the library already uses the identifier “\(identifier)”.")
        case .notInLibrary: String(localized: "The cape is not saved in the library.")
        case .noOriginal(let name): String(localized: "There is no original of “\(name)” to go back to.")
        case .notInTrash(let name): String(localized: "“\(name)” can't be put back: it is no longer in the Trash.")
        case .applyFailed(let name): String(localized: "“\(name)” could not be applied.")
        case .partiallyApplied(let name):
            String(localized: "“\(name)” is applied, but some of its cursors were rejected by macOS. Check them in the editor.")
        case .dumpFailed: String(localized: "The current cursors could not be captured.")
        case .conversionFailed: String(localized: "The MightyMouse file could not be converted.")
        }
    }
}
