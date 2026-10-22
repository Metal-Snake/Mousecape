import Foundation
import Testing
import CapeKit
@testable import Mousecape

/// Saving, renaming and duplicating capes in a throwaway library folder. Nothing here
/// applies cursors: none of the capes is the applied one.
@MainActor
final class LibraryTests {
    let base = FileManager.default.temporaryDirectory.appending(path: "MousecapeTests-\(UUID().uuidString)")
    var folder: URL { base.appending(path: "capes") }
    var versionsFolder: URL { base.appending(path: "Versions") }
    func history(_ identifier: String) -> URL { versionsFolder.appending(path: identifier) }
    /// Stands in for the Trash.
    var trash: URL { base.appending(path: "Trash") }

    deinit {
        try? FileManager.default.removeItem(at: base)
    }

    func files(in directory: URL? = nil) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: (directory ?? folder).path)) ?? []).sorted()
    }

    /// A library in `folder` whose Trash is `trash`.
    func makeLibrary() -> Library {
        let library = Library(folder: folder)
        let trash = trash
        library.moveToTrash = { url in
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: trash.appending(path: UUID().uuidString + "-" + url.lastPathComponent))
        }
        return library
    }

    @Test func savesNewCape() throws {
        let library = makeLibrary()
        let cape = try library.save(Cape(identifier: "test.one", name: "One", author: "Me"), originalIdentifier: nil)
        #expect(files() == ["test.one.cape"])
        #expect(cape.fileURL != nil)
        #expect(library.capes.map(\.name) == ["One"])
    }

    @Test func renamesFileWhenIdentifierChanges() throws {
        let library = makeLibrary()
        var cape = try library.save(Cape(identifier: "test.old", name: "Cape", author: ""), originalIdentifier: nil)
        cape.identifier = "test.new"
        try library.save(cape, originalIdentifier: "test.old")
        #expect(files() == ["test.new.cape"])
        #expect(library.capes.map(\.identifier) == ["test.new"])
    }

    @Test func refusesTakenOrInvalidIdentifier() throws {
        let library = makeLibrary()
        try library.save(Cape(identifier: "test.a", name: "A", author: ""), originalIdentifier: nil)
        try library.save(Cape(identifier: "test.b", name: "B", author: ""), originalIdentifier: nil)
        #expect(throws: LibraryError.self) {
            try library.save(Cape(identifier: "test.a", name: "B", author: ""), originalIdentifier: "test.b")
        }
        #expect(throws: LibraryError.self) {
            try library.save(Cape(identifier: "../evil", name: "C", author: ""), originalIdentifier: nil)
        }
        #expect(files() == ["test.a.cape", "test.b.cape"])
    }

    @Test func renamesStrayFileToIdentifier() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let cape = Cape(identifier: "test.stray", name: "Stray", author: "")
        try cape.propertyListData().write(to: folder.appending(path: "Some Name.cape"))
        let library = makeLibrary()
        #expect(files() == ["test.stray.cape"])
        #expect(library.capes.first?.fileURL?.lastPathComponent == "test.stray.cape")
    }

    @Test func listsDuplicateIdentifiersSeparately() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let cape = Cape(identifier: "test.twice", name: "Twice", author: "")
        try cape.propertyListData().write(to: folder.appending(path: "test.twice.cape"))
        try cape.propertyListData().write(to: folder.appending(path: "Copy of Twice.cape"))
        let library = makeLibrary()
        #expect(library.capes.count == 1)
        #expect(library.capes.first?.fileURL?.lastPathComponent == "test.twice.cape")
        #expect(library.duplicates.map(\.lastPathComponent) == ["Copy of Twice.cape"])
    }

    @Test func savingKeepsOneFilePerCape() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let library = makeLibrary()
        var cape = try library.save(Cape(identifier: "test.edit", name: "Before", author: ""), originalIdentifier: nil)
        cape.name = "After"
        try library.save(cape, originalIdentifier: "test.edit")
        #expect(files() == ["test.edit.cape"])
        #expect(library.capes.map(\.name) == ["After"])
    }

    @Test func duplicatesUnderNewIdentifier() throws {
        let library = makeLibrary()
        let cape = try library.save(Cape(identifier: "test.orig", name: "Orig", author: ""), originalIdentifier: nil)
        let copy = try library.duplicate(cape)
        #expect(copy.identifier.hasPrefix("test.orig.copy."))
        #expect(copy.name == "Orig Copy")
        #expect(library.capes.count == 2)
    }

    // MARK: - Versions

    /// A cape in the library as if imported, then edited once.
    func importedAndEdited(_ library: Library) throws -> Cape {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Cape(identifier: "test.theme", name: "Imported", author: "").propertyListData()
            .write(to: folder.appending(path: "test.theme.cape"))
        library.reload()
        var cape = try #require(library.capes.first)
        cape.name = "Edited"
        return try library.save(cape, originalIdentifier: "test.theme")
    }

    func names(_ versions: [CapeVersion]) throws -> [String] {
        try versions.map { try Cape(contentsOf: $0.url).name }
    }

    @Test func keepsOriginalOfCapesFoundAtStart() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Cape(identifier: "test.old", name: "Old", author: "").propertyListData()
            .write(to: folder.appending(path: "test.old.cape"))
        let library = makeLibrary()
        #expect(files(in: history("test.old")) == ["original.cape"])
        #expect(library.editedIdentifiers.isEmpty)
    }

    @Test func keepsEveryReplacedState() throws {
        let library = makeLibrary()
        var cape = try importedAndEdited(library)
        #expect(library.editedIdentifiers == ["test.theme"])
        cape.name = "Edited again"
        cape = try library.save(cape, originalIdentifier: "test.theme")
        let versions = library.versions(of: cape)
        #expect(versions.map(\.kind) == [.original, .saved])
        #expect(try names(versions) == ["Imported", "Edited"])
        #expect(cape.name == "Edited again")                   // the current state is the library file
    }

    @Test func newCapesStartTheirOwnHistory() throws {
        let library = makeLibrary()
        let cape = try library.save(Cape(identifier: "test.new", name: "New", author: ""), originalIdentifier: nil)
        #expect(files(in: history("test.new")) == ["original.cape"])
        let copy = try library.duplicate(cape)
        #expect(files(in: history(copy.identifier)) == ["original.cape"])
        #expect(library.editedIdentifiers.isEmpty)
    }

    @Test func savingBackToTheOriginalIsNotEdited() throws {
        let library = makeLibrary()
        var cape = try importedAndEdited(library)
        cape.name = "Imported"
        try library.save(cape, originalIdentifier: "test.theme")
        #expect(library.editedIdentifiers.isEmpty)
    }

    @Test func revertsToOriginalKeepingTheEditedState() throws {
        let library = makeLibrary()
        let edited = try importedAndEdited(library)
        let reverted = try library.revertToOriginal(edited)
        #expect(reverted.name == "Imported")
        #expect(library.capes.map(\.name) == ["Imported"])
        #expect(library.editedIdentifiers.isEmpty)
        #expect(try names(library.versions(of: reverted)) == ["Imported", "Edited"])
        #expect(files(in: trash).isEmpty)
    }

    @Test func restoresASavedVersion() throws {
        let library = makeLibrary()
        var cape = try importedAndEdited(library)              // saved: –, current: Edited
        cape.name = "Third"
        cape = try library.save(cape, originalIdentifier: "test.theme")   // saved: Edited
        let edited = try #require(library.versions(of: cape).first { $0.kind == .saved })
        let restored = try library.restore(edited, of: cape)
        #expect(restored.name == "Edited")
        #expect(try names(library.versions(of: restored)) == ["Imported", "Edited", "Third"])
    }

    @Test func historyFollowsIdentifierChange() throws {
        let library = makeLibrary()
        var cape = try importedAndEdited(library)
        cape.identifier = "test.renamed"
        cape = try library.save(cape, originalIdentifier: "test.theme")
        #expect(files() == ["test.renamed.cape"])
        #expect(files(in: versionsFolder) == ["test.renamed"])
        #expect(files(in: trash).count == 1)                  // the old file, not removed for good
        // Reverting brings the old identifier back, history included.
        let reverted = try library.revertToOriginal(cape)
        #expect(reverted.identifier == "test.theme")
        #expect(files() == ["test.theme.cape"])
        #expect(files(in: versionsFolder) == ["test.theme"])
    }

    @Test func keepsAtMostTheLimitOfSavedStates() throws {
        let library = makeLibrary()
        var cape = try importedAndEdited(library)
        for number in 1...(CapeHistory.savedLimit + 3) {
            cape.name = "Save \(number)"
            cape = try library.save(cape, originalIdentifier: "test.theme")
        }
        let versions = library.versions(of: cape)
        #expect(versions.filter { $0.kind == .saved }.count == CapeHistory.savedLimit)
        #expect(versions.first?.kind == .original)
        #expect(try names(versions).last == "Save \(CapeHistory.savedLimit + 2)")   // the one before the current
    }

    @Test func removesSavedStatesOnly() throws {
        let library = makeLibrary()
        var cape = try importedAndEdited(library)
        cape.name = "Again"
        cape = try library.save(cape, originalIdentifier: "test.theme")
        try library.removeSavedVersions(of: cape)
        #expect(library.versions(of: cape).map(\.kind) == [.original])
        #expect(library.capes.map(\.name) == ["Again"])
    }

    @Test func deletingMovesHistoryToTrash() throws {
        let library = makeLibrary()
        let cape = try importedAndEdited(library)
        try library.delete(cape)
        #expect(files().isEmpty)
        #expect(files(in: versionsFolder).isEmpty)
        #expect(files(in: trash).count == 2)                  // the file and its history folder
    }

    @Test func importingAgainStartsOver() throws {
        let library = makeLibrary()
        _ = try importedAndEdited(library)
        let file = base.appending(path: "download.cape")
        try Cape(identifier: "test.theme", name: "Imported again", author: "").propertyListData().write(to: file)
        let imported = try library.importCape(at: file)
        #expect(try names(library.versions(of: imported)) == ["Imported again"])
        #expect(library.editedIdentifiers.isEmpty)
        // The same for a converted theme imported again.
        _ = try importedAndEdited(library)
        let converted = try library.replace(with: Cape(identifier: "test.theme", name: "Converted", author: ""))
        #expect(try names(library.versions(of: converted)) == ["Converted"])
    }

    // MARK: - Unsafe identifiers

    @Test func refusesCapesWhoseIdentifierLeavesTheLibrary() throws {
        let library = makeLibrary()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let file = base.appending(path: "evil.cape")
        // Written by hand: CapeKit itself wouldn't produce such a cape.
        let plist: [String: Any] = ["Version": 2.0, "MinimumVersion": 2.0, "Identifier": "../capes",
                                    "CapeName": "Evil", "Cursors": [String: Any]()]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: file)
        try library.save(Cape(identifier: "test.keep", name: "Keep", author: ""), originalIdentifier: nil)
        #expect(throws: CapeError.self) { try library.importCape(at: file) }
        #expect(files() == ["test.keep.cape"])                 // the library is still there
        #expect(files(in: trash).isEmpty)
        #expect(throws: CapeError.self) { try library.history.capeFolder(for: "../capes") }
    }

    @Test func openingTheLibraryFileKeepsItsHistory() throws {
        let library = makeLibrary()
        var cape = try importedAndEdited(library)
        cape.name = "Again"
        cape = try library.save(cape, originalIdentifier: "test.theme")
        let file = try #require(cape.fileURL)
        try library.importCape(at: file)                        // e.g. a double-click in Finder
        #expect(library.versions(of: cape).count == 2)
        #expect(files(in: trash).isEmpty)
    }
}
