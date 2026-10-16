import Foundation
import Observation
import CapeKit

/// The capes in ~/Library/Application Support/Mousecape/capes (the same folder the original
/// app used), one `<identifier>.cape` file each.
@MainActor @Observable
final class Library {
    private(set) var capes: [Cape] = []
    private(set) var appliedIdentifier: String?
    /// Files in the folder that could not be read, shown so they don't vanish silently.
    private(set) var unreadable: [URL] = []

    let folder: URL

    init(folder: URL = Library.defaultFolder) {
        self.folder = folder
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

    func reload() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        var loaded: [Cape] = []
        var failed: [URL] = []
        for url in files where url.pathExtension.lowercased() == "cape" {
            if let cape = try? Cape(contentsOf: url) {
                loaded.append(cape)
            } else {
                failed.append(url)
            }
        }
        capes = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        unreadable = failed
        appliedIdentifier = EnginePreferences.appliedCapeIdentifier
    }

    // MARK: - Applying

    func apply(_ cape: Cape) throws {
        guard let url = cape.fileURL else { throw LibraryError.notInLibrary }
        guard Engine.apply(url) else { throw LibraryError.applyFailed(cape.name) }
        appliedIdentifier = cape.identifier
    }

    func resetToDefault() {
        Engine.reset()
        appliedIdentifier = nil
    }

    /// Re-applies the current cape, e.g. after the left-handed setting changed.
    func reapply() {
        guard let cape = appliedCape else { return }
        try? apply(cape)
    }

    // MARK: - Adding and removing

    /// The library cape a file would replace, if its identifier is already taken.
    func existingCape(forFileAt url: URL) throws -> Cape? {
        let cape = try Cape(contentsOf: url)
        return capes.first { $0.identifier == cape.identifier }
    }

    /// Copies a `.cape` file into the library (replacing a cape with the same identifier).
    @discardableResult
    func importCape(at url: URL) throws -> Cape {
        let cape = try Cape(contentsOf: url)
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
        try cape.propertyListData().write(to: fileURL(for: cape.identifier), options: .atomic)
        reload()
        return capes.first { $0.identifier == cape.identifier } ?? cape
    }

    /// Moves the cape file to the Trash; resets the cursors first if it is applied.
    func delete(_ cape: Cape) throws {
        if cape.identifier == appliedIdentifier { resetToDefault() }
        if let url = cape.fileURL {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        reload()
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

    private func copyToTemporary(_ url: URL) throws -> URL {
        let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".cape")
        try FileManager.default.copyItem(at: url, to: temporary)
        return temporary
    }
}

enum LibraryError: LocalizedError {
    case notInLibrary
    case applyFailed(String)
    case dumpFailed
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .notInLibrary: String(localized: "The cape is not saved in the library.")
        case .applyFailed(let name): String(localized: "“\(name)” could not be applied.")
        case .dumpFailed: String(localized: "The current cursors could not be captured.")
        case .conversionFailed: String(localized: "The MightyMouse file could not be converted.")
        }
    }
}
