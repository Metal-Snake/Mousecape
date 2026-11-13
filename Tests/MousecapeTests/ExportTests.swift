import AppKit
import Testing
import TestSupport
import MousecloakCore

private let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

/// `mousecloak --export` names every file .png, so TIFF images (as captured cursors store
/// them) have to be converted; PNG images are written as they are.
@Test func exportWritesPNGFiles() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "ExportTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let png = pngImage(width: 16, height: 16) { $0.setFillColor(.black); $0.fill(CGRect(x: 0, y: 0, width: 4, height: 4)) }
    let tiff = try #require(NSBitmapImageRep(data: png)?.tiffRepresentation)
    let cape: [String: Any] = ["Cursors": [
        "com.apple.coregraphics.Arrow": ["Representations": [png, tiff, Data("not an image".utf8)]],
    ]]
    exportCape(cape, folder.path)

    let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    #expect(files == ["com.apple.coregraphics.Arrow_0.png", "com.apple.coregraphics.Arrow_1.png"])
    let first = try Data(contentsOf: folder.appending(path: files[0]))
    let second = try Data(contentsOf: folder.appending(path: files[1]))
    #expect(first == png)                                       // PNG stays as it was
    #expect(second.prefix(8) == pngSignature)                   // TIFF became PNG
    #expect(NSBitmapImageRep(data: second)?.pixelsWide == 16)
}
