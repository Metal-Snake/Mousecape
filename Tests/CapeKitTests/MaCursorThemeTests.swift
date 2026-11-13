import Foundation
import Testing
import TestSupport
@testable import CapeKit

@Test func convertsMaCursorThemeToCape() throws {
    let file = maCursorFile(cursors: [
        "com.apple.coregraphics.Arrow": maCursorEntry(hotSpot: (6, 4)),
        "com.apple.coregraphics.Wait": maCursorEntry(frames: 30),
    ])
    let (cape, skipped) = try MaCursorTheme(data: file).makeCape(author: "fallback")
    #expect(skipped.isEmpty)
    #expect(cape.identifier == "local.macursor.testtheme")
    #expect(cape.name == "Test Theme")
    #expect(cape.author == "Tester")
    #expect(cape.version == 2)
    #expect(cape.otherKeys == .none)                       // UUID and MaCursor's names aren't carried along
    let arrow = try #require(cape.cursors.first { $0.identifier == "com.apple.coregraphics.Arrow" })
    #expect(arrow.hotSpot == CGPoint(x: 6, y: 4))
    #expect(arrow.representations.count == 2)
    // More frames than macOS shows stay in the cape; applying reduces them, as for any cape.
    #expect(cape.cursors.first { $0.identifier == "com.apple.coregraphics.Wait" }?.frameCount == 30)
}

@Test func readsBinaryThemesAndFillsInMissingNames() throws {
    let file = maCursorFile(name: nil, creator: nil, cursors: ["com.apple.cursor.13": maCursorEntry()],
                            format: .binary)
    let (cape, _) = try MaCursorTheme(data: file, fallbackName: "Pointy").makeCape(author: "MaCursor theme")
    #expect(cape.name == "Pointy")
    #expect(cape.author == "MaCursor theme")
}

@Test func skipsCursorsThatCannotBeRead() throws {
    var damaged = maCursorEntry()
    damaged["Representations"] = "not images"
    let file = maCursorFile(cursors: [
        "com.apple.coregraphics.Arrow": maCursorEntry(),
        "com.apple.coregraphics.IBeam": damaged,
        "../escape": maCursorEntry(),
    ])
    let theme = try MaCursorTheme(data: file)
    #expect(theme.cursors.map(\.identifier) == ["com.apple.coregraphics.Arrow"])
    #expect(theme.skipped == ["../escape", "com.apple.coregraphics.IBeam"])
}

@Test func rejectsFilesThatAreNoThemes() {
    #expect(throws: MaCursorError.notATheme) { try MaCursorTheme(data: Data("no plist".utf8)) }
    #expect(throws: MaCursorError.noCursorsFound) { try MaCursorTheme(data: maCursorFile(cursors: [:])) }
}
