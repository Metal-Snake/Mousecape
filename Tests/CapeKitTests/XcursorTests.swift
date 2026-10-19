import AppKit
import Testing
@testable import CapeKit

// MARK: - Writing test files

/// One image chunk: a solid colour (premultiplied ARGB) at a nominal size.
struct XcursorTestImage {
    var nominalSize: Int
    var width: Int
    var height: Int
    var hotSpot: (Int, Int)
    var delay = 0
    var argb: UInt32 = 0xFF_FF_00_00                   // opaque red
}

/// An Xcursor file with the given images, in order, plus a comment chunk to skip.
func xcursorFile(_ images: [XcursorTestImage]) -> Data {
    var data = Data()
    func u32(_ v: Int) { withUnsafeBytes(of: UInt32(truncatingIfNeeded: v).littleEndian) { data.append(contentsOf: $0) } }
    let entries = images.count + 1
    u32(0); data.replaceSubrange(0..<4, with: Array("Xcur".utf8))
    u32(16); u32(0x1_0000); u32(entries)
    let tocEnd = 16 + 12 * entries
    // The comment chunk comes first in the file, images after it.
    let comment = Array("made for a test".utf8)
    let commentSize = 20 + comment.count
    var position = tocEnd + commentSize
    u32(0xFFFE_0001); u32(1); u32(tocEnd)
    for image in images {
        u32(0xFFFD_0002); u32(image.nominalSize); u32(position)
        position += 36 + image.width * image.height * 4
    }
    u32(20); u32(0xFFFE_0001); u32(1); u32(1); u32(comment.count); data.append(contentsOf: comment)
    for image in images {
        u32(36); u32(0xFFFD_0002); u32(image.nominalSize); u32(1)
        u32(image.width); u32(image.height); u32(image.hotSpot.0); u32(image.hotSpot.1); u32(image.delay)
        for _ in 0..<(image.width * image.height) { u32(Int(image.argb)) }
    }
    return data
}

/// The colour at the centre of a sheet's top frame, as RGBA bytes.
private func centreColour(_ png: Data, frameHeight: Int) throws -> [UInt8] {
    let rep = try #require(NSBitmapImageRep(data: png))
    var pixel = [Int](repeating: 0, count: rep.samplesPerPixel)
    rep.getPixel(&pixel, atX: rep.pixelsWide / 2, y: frameHeight / 2)
    return pixel.map { UInt8($0) }
}

// MARK: - Reading

@Test func readsXcursorImages() throws {
    let file = xcursorFile([XcursorTestImage(nominalSize: 24, width: 24, height: 24, hotSpot: (5, 1))])
    #expect(Xcursor.isXcursor(file))
    let images = try Xcursor.images(from: file)
    #expect(images.count == 1)                                  // the comment is skipped
    #expect(images[0].nominalSize == 24)
    #expect(images[0].hotSpot == CGPoint(x: 5, y: 1))
}

@Test func rejectsNonXcursorAndTruncatedFiles() {
    #expect(throws: XcursorError.notACursor) { try Xcursor.images(from: Data("not a cursor".utf8)) }
    let file = xcursorFile([XcursorTestImage(nominalSize: 24, width: 24, height: 24, hotSpot: (0, 0))])
    #expect(throws: XcursorError.notACursor) { try Xcursor.images(from: file.prefix(file.count - 10)) }
}

@Test func convertsXcursorToCapeCursorWithOwnImagesPerScale() throws {
    // 24 and 48 pixels, red and blue: the 1x sheet must use the red, the 2x the blue images.
    let file = xcursorFile([
        XcursorTestImage(nominalSize: 24, width: 24, height: 24, hotSpot: (5, 1)),
        XcursorTestImage(nominalSize: 48, width: 48, height: 48, hotSpot: (11, 3), argb: 0xFF_00_00_FF),
    ])
    let cursor = try Xcursor.capeCursor(from: file, identifier: "com.apple.coregraphics.Arrow")
    #expect(cursor.size == CGSize(width: 24, height: 24))
    #expect(cursor.hotSpot == CGPoint(x: 5, y: 1))              // from the 24 px image, not 11/2, 3/2
    #expect(cursor.frameCount == 1)
    #expect(cursor.scales == [1, 2])                            // no 5x: nothing that large
    #expect(try centreColour(cursor.representations[0], frameHeight: 24) == [255, 0, 0, 255])
    #expect(try centreColour(cursor.representations[1], frameHeight: 48) == [0, 0, 255, 255])
}

@Test func showsClosestSizeUnscaledLikeLinux() throws {
    // Like the Obsidian theme: only size 48, a normal-sized arrow on a 48-pixel canvas.
    // Linux shows these images 1:1 at the default size, so they become 48 points.
    let file = xcursorFile([XcursorTestImage(nominalSize: 48, width: 48, height: 48, hotSpot: (7, 5))])
    let cursor = try Xcursor.capeCursor(from: file, identifier: "x")
    #expect(cursor.size == CGSize(width: 48, height: 48))
    #expect(cursor.hotSpot == CGPoint(x: 7, y: 5))
    #expect(cursor.scales == [1])                               // nothing at 96 for 2x
}

@Test func picksSizeClosestToDefault() throws {
    // 16 and 32 are equally close to 24: the first in the file wins, as in libXcursor.
    let file = xcursorFile([
        XcursorTestImage(nominalSize: 32, width: 32, height: 32, hotSpot: (4, 4)),
        XcursorTestImage(nominalSize: 16, width: 16, height: 16, hotSpot: (2, 2)),
        XcursorTestImage(nominalSize: 64, width: 64, height: 64, hotSpot: (8, 8)),
    ])
    let cursor = try Xcursor.capeCursor(from: file, identifier: "x")
    #expect(cursor.size == CGSize(width: 32, height: 32))
    #expect(cursor.hotSpot == CGPoint(x: 4, y: 4))
    #expect(cursor.scales == [1, 2])                            // 2x from the 64-pixel images
}

@Test func convertsXcursorAnimation() throws {
    // Three frames, 20/40/20 ms: repeated in 20 ms units.
    let frames = [20, 40, 20].map { XcursorTestImage(nominalSize: 24, width: 24, height: 24, hotSpot: (12, 12), delay: $0) }
    let cursor = try Xcursor.capeCursor(from: xcursorFile(frames), identifier: "com.apple.coregraphics.Wait")
    #expect(cursor.frameCount == 4)
    #expect(abs(cursor.frameDuration - 0.02) < 0.0001)
    let rep = try #require(NSBitmapImageRep(data: cursor.representations[0]))
    #expect(rep.pixelsHigh == 24 * 4)
}

// MARK: - Themes

@Suite final class XcursorThemeTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "XcursorTests-\(UUID().uuidString)")

    deinit { try? FileManager.default.removeItem(at: folder) }

    /// A theme folder: `index.theme` and `cursors/` with the given files and links.
    func makeTheme(files: [String], links: [String: String] = [:], name: String? = "Test Theme") throws -> URL {
        let theme = folder.appending(path: "theme")
        let cursors = theme.appending(path: "cursors")
        try FileManager.default.createDirectory(at: cursors, withIntermediateDirectories: true)
        if let name {
            try "[Icon Theme]\nName=\(name)\nComment=test\n".write(to: theme.appending(path: "index.theme"), atomically: true, encoding: .utf8)
        }
        for file in files {
            try xcursorFile([XcursorTestImage(nominalSize: 24, width: 24, height: 24, hotSpot: (1, 1))])
                .write(to: cursors.appending(path: file))
        }
        for (link, target) in links {
            try FileManager.default.createSymbolicLink(atPath: cursors.appending(path: link).path, withDestinationPath: target)
        }
        return theme
    }

    @Test func loadsThemeWithLinks() throws {
        let theme = try XcursorTheme.load(folder: makeTheme(files: ["left_ptr", "xterm"], links: ["default": "left_ptr"]))
        #expect(theme.name == "Test Theme")
        #expect(Set(theme.files.keys) == ["left_ptr", "xterm", "default"])
        let (cape, skipped) = try theme.makeCape(author: "Test")
        #expect(skipped.isEmpty)
        #expect(cape.identifier == "local.xcursor.testtheme")
        #expect(Set(cape.cursors.map(\.identifier)) == ["com.apple.coregraphics.Arrow", "com.apple.coregraphics.IBeam"])
    }

    @Test func choosingTheCursorsFolderFindsTheTheme() throws {
        let theme = try makeTheme(files: ["left_ptr"])
        #expect(try XcursorTheme.load(folder: theme.appending(path: "cursors")).name == "Test Theme")
    }

    @Test func namesThemeAfterFolderWithoutIndex() throws {
        let theme = try makeTheme(files: ["left_ptr"], name: nil)
        #expect(try XcursorTheme.load(folder: theme).name == "theme")
    }

    @Test func ignoresLinksLeavingTheTheme() throws {
        let outside = folder.appending(path: "outside")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try xcursorFile([XcursorTestImage(nominalSize: 24, width: 24, height: 24, hotSpot: (1, 1))]).write(to: outside)
        let theme = try XcursorTheme.load(folder: makeTheme(files: ["left_ptr"], links: ["xterm": outside.path]))
        #expect(Array(theme.files.keys) == ["left_ptr"])
    }

    @Test func reportsUnreadableFiles() throws {
        let theme = try makeTheme(files: ["left_ptr"])
        // Starts like an Xcursor file but is cut short.
        try Data("Xcur".utf8).write(to: theme.appending(path: "cursors/xterm"))
        let (cape, skipped) = try XcursorTheme.load(folder: theme).makeCape(author: "Test")
        #expect(cape.cursors.map(\.identifier) == ["com.apple.coregraphics.Arrow"])
        #expect(skipped == ["xterm"])
    }
}
