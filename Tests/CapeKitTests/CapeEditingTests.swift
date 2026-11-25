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

    c.representations = [png(width: 40, height: 40)]                // 2x, but frames need 48 px
    #expect(c.problems == [.heightDoesNotMatchFrames(CGSize(width: 40, height: 40), expected: 48)])

    c.representations = [png(width: 20, height: 24)]
    c.frameCount = 25
    c.hotSpot = CGPoint(x: 30, y: 0)
    #expect(c.problems.contains(.framesWillBeReduced(from: 25, to: 13)))
    #expect(c.problems.contains(.hotSpotOutside))
}

// macOS takes images at any density (NOTES.md): only frames that don't fit are a problem.
@Test(arguments: [(60, 72), (80, 96), (30, 36)])                    // 3x, 4x, 1.5x
func acceptsAnyDensity(width: Int, height: Int) {
    var c = cursor()
    c.representations = [png(width: width, height: height)]
    #expect(c.problems.isEmpty)
}

@Test func acceptsFractionalDensitiesAPixelOff() {
    // As in MaCursor themes: 24.8 × 24 points in 25 pixels, five frames of 24 pixels.
    var c = cursor(size: CGSize(width: 24.8, height: 24), frames: 5)
    c.representations = [png(width: 25, height: 120)]
    #expect(c.problems.isEmpty)
    c.representations = [png(width: 25, height: 130)]               // 26 per frame: too high
    #expect(c.problems == [.heightDoesNotMatchFrames(CGSize(width: 25, height: 130), expected: 121)])
    c.representations = [png(width: 25, height: 121)]               // frames don't split evenly
    #expect(!c.problems.isEmpty)
}

@Test func listsImagesAtOtherDensities() throws {
    var c = cursor()
    let triple = png(width: 60, height: 72)
    c.setRepresentation(png(width: 20, height: 24), for: 1)
    c.setRepresentation(png(width: 40, height: 48), for: 2)
    c.representations.append(triple)
    #expect(c.otherRepresentations == [triple])
    #expect(try #require(c.density(of: triple)) == 3)
    c.setRepresentation(nil, for: 2)                                // wells leave the others alone
    #expect(c.otherRepresentations == [triple])
    c.removeRepresentation(triple)
    #expect(c.representations.count == 1)
    #expect(c.otherRepresentations.isEmpty)
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

@Test func selectsFrames() {
    #expect(FrameSelection.everyNth(of: 30) == Array(stride(from: 0, to: 30, by: 2)))
    #expect(FrameSelection.everyNth(of: 20) == Array(0..<20))
    let spread = FrameSelection.spread(of: 30)
    #expect(spread.count == 24)
    #expect(spread.first == 0 && spread.last == 28)
    #expect(Set(spread).count == 24)
    #expect(FrameSelection.first(of: 30) == Array(0..<24))
    #expect(abs(FrameSelection.loopPreservingDuration(frameDuration: 0.02, frameCount: 30, kept: 24) - 0.025) < 1e-9)
    #expect(!FrameSelection.isUneven(FrameSelection.everyNth(of: 30), frameCount: 30))
    #expect(FrameSelection.isUneven(spread, frameCount: 30))
    #expect(FrameSelection.isUneven(FrameSelection.first(of: 30), frameCount: 30))   // jump back at the end
}

@Test func keepsChosenFrames() throws {
    // 6 frames of 4 × 4 px, frame i filled with grey i/6.
    let frames = 6, side = 4
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side * frames,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for frame in 0..<frames {
        for y in 0..<side { for x in 0..<side {
            let grey = CGFloat(frame) / CGFloat(frames)
            rep.setColor(NSColor(deviceRed: grey, green: grey, blue: grey, alpha: 1), atX: x, y: frame * side + y)
        } }
    }
    let c = CapeCursor(identifier: "x", frameCount: frames, frameDuration: 0.1,
                       size: CGSize(width: side, height: side),
                       representations: [rep.representation(using: .png, properties: [:])!])
    let kept = try #require(c.keepingFrames([5, 1, 3], frameDuration: 0.2))
    #expect(kept.frameCount == 3)
    #expect(kept.frameDuration == 0.2)
    func grey(_ image: CGImage) -> CGFloat {
        NSBitmapImageRep(cgImage: image).colorAt(x: 1, y: 1)!.usingColorSpace(.deviceRGB)!.redComponent
    }
    #expect(kept.frames().map { (grey($0) * 6).rounded() } == [5, 1, 3])   // order as given
    #expect(c.keepingFrames([], frameDuration: 0.1) == nil)
    #expect(c.keepingFrames([6], frameDuration: 0.1) == nil)
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
    #expect(!cape.missingCursorIdentifiers.contains("com.apple.cursor.0"))   // applying fills it

    cape.addCursor(identifier: "com.apple.cursor.13")
    cape.addCursor(identifier: "com.apple.coregraphics.Arrow")
    #expect(cape.cursors.map(\.name) == ["Arrow", "Pointing Hand"])
    #expect(!cape.missingCursorIdentifiers.contains("com.apple.coregraphics.Arrow"))
    #expect(cape.problems.keys.sorted() == ["com.apple.coregraphics.Arrow", "com.apple.cursor.13"])

    cape.removeCursor(identifier: "com.apple.cursor.13")
    #expect(cape.cursors.map(\.name) == ["Arrow"])
}

@Test func sampleCapeHasNoProblems() throws {
    let cape = try Cape(contentsOf: sampleURL)
    #expect(cape.problems.isEmpty)
}

/// With long animations the engine keeps up to 256 frames, fewer for big images.
@Test func longAnimationsKeepMoreFrames() throws {
    // 30 frames of 10 × 10 px: 100 pixels a frame, far below the pixel limit.
    var c = CapeCursor(identifier: "com.apple.coregraphics.Wait", frameCount: 30, frameDuration: 0.02,
                       size: CGSize(width: 10, height: 10), representations: [png(width: 10, height: 300)])
    #expect(c.pixelsPerFrame == 100)
    #expect(c.frameLimit(longAnimations: false) == 24)
    #expect(c.frameLimit(longAnimations: true) == 256)
    #expect(c.problems(longAnimations: true).isEmpty)
    #expect(c.problems(longAnimations: false) == [.framesWillBeReduced(from: 30, to: 15)])
    #expect(c.appliedFrameCount(longAnimations: true) == 30)
    #expect(try #require(c.reducingFrames(longAnimations: true)).frameCount == 30)

    // 300 frames: over 256 even with long animations, so every 2nd frame.
    c.frameCount = 300
    c.representations = [png(width: 10, height: 3000)]
    #expect(c.appliedFrameCount(longAnimations: true) == 150)
}

@Test func pixelLimitLowersTheFrameLimit() {
    // 256 frames of 65,536 pixels fill the pixel limit exactly; a pixel more allows 255.
    #expect(CapeCursor.frameLimit(pixelsPerFrame: 65_536, longAnimations: true) == 256)
    #expect(CapeCursor.frameLimit(pixelsPerFrame: 65_537, longAnimations: true) == 255)
    // Big images never go below what macOS takes anyway.
    #expect(CapeCursor.frameLimit(pixelsPerFrame: 10_000_000, longAnimations: true) == 24)
    #expect(CapeCursor.frameLimit(pixelsPerFrame: 1, longAnimations: false) == 24)
}

/// Frames with their own durations are expanded exactly when that fits the larger limit.
@Test func longAnimationsTimeFramesExactly() {
    // 1 and 40 jiffies: 41 frames exactly, which only fit with long animations.
    let c = CapeCursor(identifier: "com.apple.coregraphics.Wait", frameCount: 2, frameDurations: [1.0 / 60, 40.0 / 60],
                       size: CGSize(width: 4, height: 4), representations: [png(width: 4, height: 8)])
    #expect(c.appliedFrameCount(longAnimations: false) == 24)   // sampled
    #expect(c.appliedFrameCount(longAnimations: true) == 41)    // exact
}

/// macOS refuses a hot spot on the right or bottom edge (x == width), as Xcursor themes
/// like Katana have; inside the last point is fine.
@Test(arguments: [(32.0, 3.0, false), (31.0, 3.0, true), (31.9, 5.9, true), (1.0, 6.0, false), (-1.0, 0.0, false)])
func hotSpotOnTheEdgeIsFlagged(x: Double, y: Double, fine: Bool) {
    let c = CapeCursor(identifier: "com.apple.cursor.17", frameCount: 1, hotSpot: CGPoint(x: x, y: y),
                       size: CGSize(width: 32, height: 6), representations: [png(width: 32, height: 6)])
    #expect(c.problems.contains(.hotSpotOutside) == !fine)
}
