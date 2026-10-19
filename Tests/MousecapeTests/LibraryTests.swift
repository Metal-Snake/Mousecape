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
    var originals: URL { base.appending(path: "Originals") }
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

    // MARK: - Originals

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

    @Test func keepsOriginalOnFirstSaveOnly() throws {
        let library = makeLibrary()
        var cape = try importedAndEdited(library)
        #expect(files(in: originals) == ["test.theme.cape"])
        #expect(library.editedIdentifiers == ["test.theme"])
        cape.name = "Edited again"
        try library.save(cape, originalIdentifier: "test.theme")
        // Still the imported state.
        #expect(try Cape(contentsOf: originals.appending(path: "test.theme.cape")).name == "Imported")
    }

    @Test func newCapesHaveNoOriginal() throws {
        let library = makeLibrary()
        let cape = try library.save(Cape(identifier: "test.new", name: "New", author: ""), originalIdentifier: nil)
        #expect(files(in: originals).isEmpty)
        try library.duplicate(cape)
        #expect(files(in: originals).isEmpty)
        #expect(library.editedIdentifiers.isEmpty)
    }

    @Test func savingBackToTheOriginalDropsIt() throws {
        let library = makeLibrary()
        var cape = try importedAndEdited(library)
        cape.name = "Imported"
        try library.save(cape, originalIdentifier: "test.theme")
        #expect(files(in: originals).isEmpty)
        #expect(library.editedIdentifiers.isEmpty)
    }

    @Test func revertsToOriginal() throws {
        let library = makeLibrary()
        let edited = try importedAndEdited(library)
        let reverted = try library.revertToOriginal(edited)
        #expect(reverted.name == "Imported")
        #expect(library.capes.map(\.name) == ["Imported"])
        #expect(files() == ["test.theme.cape"])
        #expect(files(in: originals).isEmpty)
        #expect(library.editedIdentifiers.isEmpty)
        #expect(files(in: trash).count == 1)                  // the edited version
    }

    @Test func originalFollowsIdentifierChange() throws {
        let library = makeLibrary()
        var cape = try importedAndEdited(library)
        cape.identifier = "test.renamed"
        cape = try library.save(cape, originalIdentifier: "test.theme")
        #expect(files() == ["test.renamed.cape"])
        #expect(files(in: originals) == ["test.renamed.cape"])
        #expect(files(in: trash).count == 1)                  // the old file, not removed for good
        // Reverting brings the old identifier back.
        let reverted = try library.revertToOriginal(cape)
        #expect(reverted.identifier == "test.theme")
        #expect(files() == ["test.theme.cape"])
    }

    @Test func deletingMovesOriginalToTrash() throws {
        let library = makeLibrary()
        let cape = try importedAndEdited(library)
        try library.delete(cape)
        #expect(files().isEmpty)
        #expect(files(in: originals).isEmpty)
        #expect(files(in: trash).count == 2)
    }

    @Test func importingAgainStartsOver() throws {
        let library = makeLibrary()
        _ = try importedAndEdited(library)
        let file = base.appending(path: "download.cape")
        try Cape(identifier: "test.theme", name: "Imported again", author: "").propertyListData().write(to: file)
        try library.importCape(at: file)
        #expect(files(in: originals).isEmpty)
        #expect(library.editedIdentifiers.isEmpty)
        // The same for a converted theme imported again.
        _ = try importedAndEdited(library)
        try library.replace(with: Cape(identifier: "test.theme", name: "Converted", author: ""))
        #expect(files(in: originals).isEmpty)
        #expect(library.capes.map(\.name) == ["Converted"])
    }
}
