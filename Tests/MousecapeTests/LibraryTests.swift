import Foundation
import Testing
import CapeKit
@testable import Mousecape

/// Saving, renaming and duplicating capes in a throwaway library folder. Nothing here
/// applies cursors: none of the capes is the applied one.
@MainActor
final class LibraryTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "MousecapeTests-\(UUID().uuidString)")

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    func files() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    @Test func savesNewCape() throws {
        let library = Library(folder: folder)
        let cape = try library.save(Cape(identifier: "test.one", name: "One", author: "Me"), originalIdentifier: nil)
        #expect(files() == ["test.one.cape"])
        #expect(cape.fileURL != nil)
        #expect(library.capes.map(\.name) == ["One"])
    }

    @Test func renamesFileWhenIdentifierChanges() throws {
        let library = Library(folder: folder)
        var cape = try library.save(Cape(identifier: "test.old", name: "Cape", author: ""), originalIdentifier: nil)
        cape.identifier = "test.new"
        try library.save(cape, originalIdentifier: "test.old")
        #expect(files() == ["test.new.cape"])
        #expect(library.capes.map(\.identifier) == ["test.new"])
    }

    @Test func refusesTakenOrInvalidIdentifier() throws {
        let library = Library(folder: folder)
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

    @Test func duplicatesUnderNewIdentifier() throws {
        let library = Library(folder: folder)
        let cape = try library.save(Cape(identifier: "test.orig", name: "Orig", author: ""), originalIdentifier: nil)
        let copy = try library.duplicate(cape)
        #expect(copy.identifier.hasPrefix("test.orig.copy."))
        #expect(copy.name == "Orig Copy")
        #expect(library.capes.count == 2)
    }
}
