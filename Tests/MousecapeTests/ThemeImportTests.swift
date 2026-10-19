import AppKit
import Testing
import CapeKit
@testable import Mousecape

/// Finding themes in folders and archives. The archives are made with the same system tools
/// the importer unpacks them with.
final class ThemeImportTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "ThemeImportTests-\(UUID().uuidString)")

    deinit { try? FileManager.default.removeItem(at: folder) }

    /// A one-image Xcursor file (24 px, opaque).
    func xcursor() -> Data {
        var data = Data("Xcur".utf8)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        u32(16); u32(0x1_0000); u32(1)
        u32(0xFFFD_0002); u32(24); u32(28)
        u32(36); u32(0xFFFD_0002); u32(24); u32(1); u32(24); u32(24); u32(3); u32(2); u32(0)
        for _ in 0..<(24 * 24) { u32(0xFF00_0000) }
        return data
    }

    /// `<folder>/src/Nice Cursors/{index.theme, cursors/…}`, returns `src`.
    func makeXcursorTheme() throws -> URL {
        let src = folder.appending(path: "src")
        let cursors = src.appending(path: "Nice Cursors/cursors")
        try FileManager.default.createDirectory(at: cursors, withIntermediateDirectories: true)
        try "[Icon Theme]\nName=Nice\n".write(to: src.appending(path: "Nice Cursors/index.theme"), atomically: true, encoding: .utf8)
        try xcursor().write(to: cursors.appending(path: "left_ptr"))
        try FileManager.default.createSymbolicLink(atPath: cursors.appending(path: "default").path, withDestinationPath: "left_ptr")
        try xcursor().write(to: cursors.appending(path: "xterm"))
        return src
    }

    func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    func capeIdentifiers(at url: URL) throws -> (name: String, identifiers: Set<String>) {
        try ThemeImport.withTheme(at: url) { theme in
            let (cape, _) = try theme.makeCape(author: "Test")
            return (cape.name, Set(cape.cursors.map(\.identifier)))
        }
    }

    @Test(arguments: ["tar.xz", "tar.gz", "tar.bz2", "tar", "7z", "zip"])
    func importsXcursorThemeFromArchive(suffix: String) throws {
        let src = try makeXcursorTheme()
        let archive = folder.appending(path: "nice.\(suffix)")
        switch suffix {
        case "zip": try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", src.appending(path: "Nice Cursors").path, archive.path])
        case "7z": try run("/usr/bin/tar", ["-c", "--format", "7zip", "-f", archive.path, "-C", src.path, "Nice Cursors"])
        default: try run("/usr/bin/tar", ["-c", "-a", "-f", archive.path, "-C", src.path, "Nice Cursors"])
        }
        #expect(ThemeImport.handles(archive))
        let result = try capeIdentifiers(at: archive)
        #expect(result.name == "Nice")
        #expect(result.identifiers == ["com.apple.coregraphics.Arrow", "com.apple.coregraphics.IBeam"])
    }

    @Test func archivesAreRemovedAfterImport() throws {
        let src = try makeXcursorTheme()
        let archive = folder.appending(path: "nice.tar.gz")
        try run("/usr/bin/tar", ["-c", "-z", "-f", archive.path, "-C", src.path, "Nice Cursors"])
        let unpacked = try ThemeImport.withTheme(at: archive) { theme in
            (theme as? XcursorTheme)?.files["xterm"]?.deletingLastPathComponent()
        }
        let path = try #require(unpacked).path
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func importsXcursorThemeFromFolder() throws {
        let src = try makeXcursorTheme()
        #expect(try capeIdentifiers(at: src).name == "Nice")
        #expect(try capeIdentifiers(at: src.appending(path: "Nice Cursors/cursors")).name == "Nice")
    }

    @Test func recognisesLooseXcursorFiles() throws {
        let src = try makeXcursorTheme()
        let file = src.appending(path: "Nice Cursors/cursors/xterm")
        #expect(ThemeImport.isLooseXcursor(file))
        #expect(ThemeImport.handles(file))
        #expect(!ThemeImport.isLooseXcursor(src.appending(path: "Nice Cursors/index.theme")))

        // A single file with a name macOS doesn't know becomes the arrow.
        let odd = folder.appending(path: "spinner")
        try xcursor().write(to: odd)
        let theme = ThemeImport.xcursorTheme(files: [odd])
        #expect(try theme.makeCape(author: "").cape.cursors.map(\.identifier) == ["com.apple.coregraphics.Arrow"])
    }

    @Test func namesThemeAfterArchiveWhenItHasNoName() throws {
        let src = folder.appending(path: "flat")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try xcursor().write(to: src.appending(path: "left_ptr"))
        let archive = folder.appending(path: "Flat Theme.tar.xz")
        try run("/usr/bin/tar", ["-c", "-a", "-f", archive.path, "-C", src.path, "left_ptr"])
        #expect(try capeIdentifiers(at: archive).name == "Flat Theme")
    }

    /// A `.cur` file holding one PNG image of `size` pixels.
    func curFile(size: Int) throws -> Data {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        var data = Data()
        func u8(_ v: Int) { data.append(UInt8(v & 0xFF)) }
        func u16(_ v: Int) { u8(v); u8(v >> 8) }
        func u32(_ v: Int) { u16(v & 0xFFFF); u16(v >> 16) }
        u16(0); u16(2); u16(1)
        u8(size & 0xFF); u8(size & 0xFF); u8(0); u8(0); u16(1); u16(1); u32(png.count); u32(22)
        data.append(png)
        return data
    }

    @Test func recognisesSizeFolders() {
        #expect(ThemeImport.sizeValue("x2") == 2)
        #expect(ThemeImport.sizeValue("2X") == 2)
        #expect(ThemeImport.sizeValue("@2x") == 2)
        #expect(ThemeImport.sizeValue("48") == 48)
        #expect(ThemeImport.sizeValue("32px") == 32)
        #expect(ThemeImport.sizeValue("150%") == 150)
        #expect(ThemeImport.sizeValue("Kiriko") == nil)
        #expect(ThemeImport.sizeValue("x") == nil)
        #expect(ThemeImport.sizeValue("v2") == nil)
    }

    /// Like the Windows Modern pack: `windows/cursors/<name>/x1 … x3`, no `install.inf`.
    @Test func takesLargestSizeFolderAndNamesThemeAboveIt() throws {
        let src = folder.appending(path: "src")
        for (scale, size) in [("x1", 32), ("x2", 64), ("x3", 96)] {
            let sizeFolder = src.appending(path: "windows/cursors/modern-v2/\(scale)")
            try FileManager.default.createDirectory(at: sizeFolder, withIntermediateDirectories: true)
            try curFile(size: size).write(to: sizeFolder.appending(path: "normal-select.cur"))
            try curFile(size: size).write(to: sizeFolder.appending(path: "text-select.cur"))
        }
        let archive = folder.appending(path: "modern.7z")
        try run("/usr/bin/tar", ["-c", "--format", "7zip", "-f", archive.path, "-C", src.path, "windows"])
        let (name, scales) = try ThemeImport.withTheme(at: archive) { theme in
            let (cape, _) = try theme.makeCape(author: "Test")
            return (cape.name, cape.cursors.first?.scales ?? [])
        }
        #expect(name == "modern-v2")
        #expect(scales == [1, 2])          // 2x needs 64 px images: x1 (32 px) would give 1x only
    }

    @Test func reportsArchivesWithoutTheme() throws {
        let src = folder.appending(path: "empty")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "hello".write(to: src.appending(path: "readme.txt"), atomically: true, encoding: .utf8)
        let archive = folder.appending(path: "nothing.7z")
        try run("/usr/bin/tar", ["-c", "--format", "7zip", "-f", archive.path, "-C", src.path, "readme.txt"])
        #expect(throws: ThemeImportError.self) { try self.capeIdentifiers(at: archive) }

        let broken = folder.appending(path: "broken.tar.xz")
        try Data("not an archive".utf8).write(to: broken)
        #expect(throws: ThemeImportError.self) { try self.capeIdentifiers(at: broken) }
    }
}
