import Foundation
import Testing
import TestSupport
@testable import CapeKit

/// `mousecloak --create`: a cape from a folder with one folder per cursor.

/// A fresh folder with the given files, by relative path; removed by the caller.
private func makeFolder(_ files: [String: Data]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "CapeFolderTests-\(UUID().uuidString)")
    for (path, data) in files {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    return root
}

private let arrow = "com.apple.coregraphics.Arrow"
private let wait = "com.apple.coregraphics.Wait"

@Test func squareImagesMakeOneFrameAtTheSmallestSize() throws {
    let folder = try makeFolder(["\(arrow)/1x.png": pngImage(width: 24, height: 24),
                                 "\(arrow)/2x.png": pngImage(width: 48, height: 48)])
    defer { try? FileManager.default.removeItem(at: folder) }
    let draft = try #require(try CapeFolder.drafts(at: folder).drafts.first)
    #expect(draft.frameCountIsCertain)
    let cursor = draft.cursor(with: .init())
    #expect(cursor.identifier == arrow)
    #expect(cursor.frameCount == 1)
    #expect(cursor.size == CGSize(width: 24, height: 24))
    #expect(cursor.hotSpot == .zero)
    #expect(cursor.representations.count == 2)
    #expect(cursor.scales == [1, 2])
}

@Test func aTallSheetIsGuessedAsSquareFramesButNotCertain() throws {
    let folder = try makeFolder(["\(wait)/1x.png": pngImage(width: 24, height: 24 * 6)])
    defer { try? FileManager.default.removeItem(at: folder) }
    let draft = try #require(try CapeFolder.drafts(at: folder).drafts.first)
    #expect(draft.guessedFrameCount == 6)
    #expect(!draft.frameCountIsCertain)
    let cursor = draft.cursor(with: .init(frameDuration: 0.05))
    #expect(cursor.frameCount == 6)
    #expect(cursor.size == CGSize(width: 24, height: 24))
    #expect(cursor.frameDuration == 0.05)
}

@Test func aNonSquareSheetIsOneFrameButNotCertain() throws {
    let folder = try makeFolder(["\(arrow)/1x.png": pngImage(width: 17, height: 23)])
    defer { try? FileManager.default.removeItem(at: folder) }
    let draft = try #require(try CapeFolder.drafts(at: folder).drafts.first)
    #expect(draft.guessedFrameCount == 1)
    #expect(!draft.frameCountIsCertain)
    #expect(draft.cursor(with: .init()).size == CGSize(width: 17, height: 23))
}

/// The folder's cursor.plist wins over the guess and over the command line's defaults.
@Test func cursorPlistOverridesGuessesAndDefaults() throws {
    let settings: [String: Any] = ["HotSpotX": 4, "HotSpotY": 5, "PointsWide": 12, "PointsHigh": 12,
                                   "FrameCount": 2, "FrameDuration": 0.2]
    let plist = try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
    let folder = try makeFolder(["\(wait)/2x.png": pngImage(width: 24, height: 48),
                                 "\(wait)/cursor.plist": plist])
    defer { try? FileManager.default.removeItem(at: folder) }
    let draft = try #require(try CapeFolder.drafts(at: folder).drafts.first)
    let defaults = CapeFolder.Settings(hotSpot: CGPoint(x: 1, y: 1), frameDuration: 0.5)
    let cursor = draft.cursor(with: draft.fileSettings.filled(from: defaults))
    #expect(cursor.hotSpot == CGPoint(x: 4, y: 5))
    #expect(cursor.size == CGSize(width: 12, height: 12))
    #expect(cursor.frameCount == 2)
    #expect(cursor.frameDuration == 0.2)
}

/// Wrong types and values in cursor.plist are ignored, not trusted.
@Test func brokenCursorPlistValuesAreIgnored() {
    let settings = CapeFolder.Settings(propertyList: ["HotSpotX": "4", "HotSpotY": 5, "PointsWide": -1, "PointsHigh": 8,
                                                      "FrameCount": 2.5, "FrameDuration": 0, "Extra": true])
    #expect(settings == CapeFolder.Settings())
    #expect(CapeFolder.Settings(propertyList: ["FrameCount": true]).frameCount == nil)
}

/// Folders that aren't valid identifiers, files that aren't images, and a second image of the
/// same width are left out, with a note each.
@Test func leavesOutWhatItCantUse() throws {
    let folder = try makeFolder(["\(arrow)/1x.png": pngImage(width: 16, height: 16),
                                 "\(arrow)/copy.png": pngImage(width: 16, height: 16),
                                 "\(arrow)/README.txt": Data("not an image".utf8),
                                 ".hidden/1x.png": pngImage(width: 16, height: 16),
                                 "~bad/1x.png": pngImage(width: 16, height: 16),
                                 "empty/notes.txt": Data("x".utf8),
                                 "loose.png": pngImage(width: 16, height: 16)])
    defer { try? FileManager.default.removeItem(at: folder) }
    let (drafts, notes) = try CapeFolder.drafts(at: folder)
    #expect(drafts.map(\.identifier) == [arrow])
    #expect(drafts.first?.representations.count == 1)
    // copy.png, README.txt, ~bad, and two for empty (notes.txt, then no images)
    #expect(notes.count == 5)
    for expected in ["copy.png", "README.txt", "~bad", "notes.txt", "folder empty: no images"] {
        #expect(notes.contains { $0.contains(expected) }, "no note about \(expected)")
    }
}

@Test func refusesAFolderWithoutCursors() throws {
    let folder = try makeFolder(["loose.png": pngImage(width: 16, height: 16)])
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(throws: CapeFolder.FolderError.noCursorFolders(folder.path)) { try CapeFolder.drafts(at: folder) }
    #expect(throws: CapeFolder.FolderError.notAFolder(folder.appending(path: "loose.png").path)) {
        try CapeFolder.drafts(at: folder.appending(path: "loose.png"))
    }
}

@Test func defaultIdentifierIsSafe() {
    #expect(CapeFolder.defaultIdentifier(forName: "My Cape 2") == "local.mycape2")
    #expect(CapeFolder.defaultIdentifier(forName: "../..") == "local.cape")
    #expect(Cape.isValidIdentifier(CapeFolder.defaultIdentifier(forName: "../..")))
}
