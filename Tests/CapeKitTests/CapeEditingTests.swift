import AppKit
import Testing
@testable import CapeKit

/// A transparent PNG of the given pixel size.
func png(width: Int, height: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
}

func cursor(size: CGSize = CGSize(width: 20, height: 24), frames: Int = 1) -> CapeCursor {
    CapeCursor(identifier: "com.apple.coregraphics.Arrow", frameCount: frames, size: size, representations: [])
}

@Test func setsRepresentationsByScale() {
    var c = cursor()
    c.setRepresentation(png(width: 40, height: 48), for: 2)
    c.setRepresentation(png(width: 20, height: 24), for: 1)
    #expect(c.scales == [1, 2])
    #expect(c.representation(for: 2).map(CapeCursor.pixelWidth) == 40)

    // Replacing keeps one image per scale.
    c.setRepresentation(png(width: 40, height: 48), for: 2)
    #expect(c.representations.count == 2)

    c.setRepresentation(nil, for: 1)
    #expect(c.scales == [2])
}

@Test func validCursorHasNoProblems() {
    var c = cursor(frames: 3)
    c.setRepresentation(png(width: 40, height: 48 * 3), for: 2)
    #expect(c.problems.isEmpty)
    #expect(c.expectedPixelSize(for: 2) == CGSize(width: 40, height: 144))
}

@Test func reportsProblems() {
    var c = cursor()
    #expect(c.problems == [.noImages])

    c.setRepresentation(png(width: 30, height: 24), for: 1)          // 1.5x: no supported scale
    #expect(c.problems == [.unexpectedWidth(CGSize(width: 30, height: 24))])

    c.representations = [png(width: 40, height: 40)]                // 2x, but frames need 48 px
    #expect(c.problems == [.heightDoesNotMatchFrames(CGSize(width: 40, height: 40), expected: 48)])

    c.representations = [png(width: 20, height: 24)]
    c.frameCount = 25
    c.hotSpot = CGPoint(x: 30, y: 0)
    #expect(c.problems.contains(.framesWillBeReduced(from: 25, to: 13)))
    #expect(c.problems.contains(.hotSpotOutside))
}

@Test func normalizesImagesToPNG() throws {
    let rep = NSBitmapImageRep(data: png(width: 8, height: 6))!
    let tiff = try #require(rep.tiffRepresentation)
    let result = try #require(CapeCursor.normalizedPNG(from: tiff))
    #expect(result.pixelSize == CGSize(width: 8, height: 6))
    #expect(result.png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    #expect(CapeCursor.normalizedPNG(from: Data("no image".utf8)) == nil)
}

@Test func reducesLongAnimations() {
    #expect(CapeCursor.reducedFrameCount(24) == 24)
    #expect(CapeCursor.reducedFrameCount(30) == 15)     // every 2nd frame
    #expect(CapeCursor.reducedFrameCount(50) == 17)     // every 3rd frame
}

@Test func reducesFramesPermanently() throws {
    // 30 frames of 10 × 10 px, each filled with its own grey level so we can tell them apart.
    let frames = 30, side = 10
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side * frames,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for frame in 0..<frames {
        let grey = CGFloat(frame) / CGFloat(frames)
        for y in 0..<side { for x in 0..<side {
            rep.setColor(NSColor(deviceRed: grey, green: grey, blue: grey, alpha: 1), atX: x, y: frame * side + y)
        } }
    }
    var c = CapeCursor(identifier: "com.apple.coregraphics.Wait", frameCount: frames, frameDuration: 0.02,
                       size: CGSize(width: side, height: side), representations: [])
    c.representations = [rep.representation(using: .png, properties: [:])!]
    #expect(c.problems == [.framesWillBeReduced(from: 30, to: 15)])

    let reduced = try #require(c.reducingFrames())
    #expect(reduced.frameCount == 15)
    #expect(abs(reduced.frameDuration - 0.04) < 0.0001)        // same speed overall
    #expect(reduced.problems.isEmpty)
    // Frame k of the result is frame 2k of the original.
    let images = reduced.frames()
    #expect(images.count == 15)
    func grey(_ image: CGImage) -> CGFloat {
        NSBitmapImageRep(cgImage: image).colorAt(x: 5, y: 5)!.usingColorSpace(.deviceRGB)!.redComponent
    }
    #expect(abs(grey(images[0]) - 0) < 0.02)
    #expect(abs(grey(images[1]) - 2.0 / 30) < 0.02)
    #expect(abs(grey(images[14]) - 28.0 / 30) < 0.02)
}

@Test func separatesErrorsFromWarnings() {
    #expect(CursorProblem.noImages.isError)
    #expect(!CursorProblem.framesWillBeReduced(from: 30, to: 15).isError)
    #expect(!CursorProblem.hotSpotOutside.isError)
}

@Test func addsAndRemovesCursors() {
    var cape = Cape.untitled(author: "Metal Snake")
    #expect(cape.identifier.hasPrefix("local.metalsnake.untitled."))
    #expect(cape.missingCursorIdentifiers.first == "com.apple.coregraphics.Arrow")

    cape.addCursor(identifier: "com.apple.cursor.13")
    cape.addCursor(identifier: "com.apple.coregraphics.Arrow")
    #expect(cape.cursors.map(\.name) == ["Arrow", "Pointing"])
    #expect(!cape.missingCursorIdentifiers.contains("com.apple.coregraphics.Arrow"))
    #expect(cape.problems.keys.sorted() == ["com.apple.coregraphics.Arrow", "com.apple.cursor.13"])

    cape.removeCursor(identifier: "com.apple.cursor.13")
    #expect(cape.cursors.map(\.name) == ["Arrow"])
}

@Test func sampleCapeHasNoProblems() throws {
    let cape = try Cape(contentsOf: sampleURL)
    #expect(cape.problems.isEmpty)
}
