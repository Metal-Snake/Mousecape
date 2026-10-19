import AppKit
import Testing
@testable import CapeKit

/// A sheet of `frames` frames, `side` pixels square, each with its left `filled` columns red.
private func sheet(side: Int, frames: Int = 1, filled: Int) throws -> Data {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(data: nil, width: side, height: side * frames, bitsPerComponent: 8,
                                         bytesPerRow: 0, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: filled, height: side * frames))
    let image = try #require(context.makeImage())
    return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
}

private func alpha(_ png: Data, x: Int, y: Int) throws -> Int {
    let rep = try #require(NSBitmapImageRep(data: png))
    var pixel = [Int](repeating: 0, count: rep.samplesPerPixel)
    rep.getPixel(&pixel, atX: x, y: y)
    return pixel[3]
}

private func cursor(_ identifier: String, hotSpot: CGPoint = CGPoint(x: 1, y: 1), frames: Int = 1) throws -> CapeCursor {
    CapeCursor(identifier: identifier, frameCount: frames, hotSpot: hotSpot, size: CGSize(width: 16, height: 16),
               representations: [try sheet(side: 16, frames: frames, filled: 4), try sheet(side: 32, frames: frames, filled: 8)])
}

@Test func keepsUnknownKeys() throws {
    var plist = try Cape(identifier: "test", name: "T", author: "",
                         cursors: [cursor("com.apple.coregraphics.Arrow")]).propertyList
    plist["FutureCapeKey"] = "kept"
    var cursors = try #require(plist["Cursors"] as? [String: Any])
    var arrow = try #require(cursors["com.apple.coregraphics.Arrow"] as? [String: Any])
    arrow["FutureCursorKey"] = 42
    cursors["com.apple.coregraphics.Arrow"] = arrow
    plist["Cursors"] = cursors

    var cape = try Cape(propertyList: plist)
    cape.name = "Edited"                                         // our editor saves it again
    let saved = try Cape(propertyListData: cape.propertyListData()).propertyList
    #expect(saved["FutureCapeKey"] as? String == "kept")
    #expect(saved["CapeName"] as? String == "Edited")
    let savedArrow = try #require((saved["Cursors"] as? [String: Any])?["com.apple.coregraphics.Arrow"] as? [String: Any])
    #expect(savedArrow["FutureCursorKey"] as? Int == 42)
}

@Test func roundTripsLeftHandedKeys() throws {
    var arrow = try cursor("com.apple.coregraphics.Arrow")
    arrow.mirrorForLeftHanded = false
    var ibeam = try cursor("com.apple.coregraphics.IBeam")
    ibeam.leftHandedRepresentations = [try sheet(side: 16, filled: 2)]
    ibeam.leftHandedHotSpot = CGPoint(x: 9, y: 2)
    let cape = Cape(identifier: "test", name: "T", author: "", cursors: [arrow, ibeam])
    let copy = try Cape(propertyListData: cape.propertyListData())
    #expect(copy.cursors.map(\.mirrorForLeftHanded) == [false, nil])
    #expect(copy.cursors[1].leftHandedRepresentations == ibeam.leftHandedRepresentations)
    #expect(copy.cursors[1].leftHandedHotSpot == CGPoint(x: 9, y: 2))
    #expect(copy == cape)
}

@Test func decidesLeftHandedLook() throws {
    #expect(try cursor("com.apple.coregraphics.Arrow").leftHandedLook == .mirrored)      // a pointer
    #expect(try cursor("com.apple.coregraphics.ArrowS").leftHandedLook == .mirrored)     // its variant
    #expect(try cursor("com.apple.coregraphics.IBeam").leftHandedLook == .unchanged)
    var ibeam = try cursor("com.apple.coregraphics.IBeam")
    ibeam.mirrorForLeftHanded = true
    #expect(ibeam.leftHandedLook == .mirrored)
    var arrow = try cursor("com.apple.coregraphics.Arrow")
    arrow.mirrorForLeftHanded = false
    #expect(arrow.leftHandedLook == .unchanged)
    let mirrored = arrow.useMirroredImagesAsLeftHanded()
    #expect(mirrored)
    #expect(arrow.leftHandedLook == .ownImages)
}

@Test func mirrorsImagesAndHotSpot() throws {
    let arrow = try cursor("com.apple.coregraphics.Arrow", hotSpot: CGPoint(x: 2, y: 3))
    let mirrored = try #require(arrow.mirroredRepresentations())
    // Red on the left becomes red on the right, at every scale.
    #expect(try alpha(mirrored[0], x: 0, y: 5) == 0 && alpha(mirrored[0], x: 15, y: 5) == 255)
    #expect(try alpha(mirrored[1], x: 0, y: 5) == 0 && alpha(mirrored[1], x: 31, y: 5) == 255)
    #expect(arrow.mirroredHotSpot == CGPoint(x: 13, y: 3))           // as the engine computes it
    let left = try #require(arrow.leftHanded)
    #expect(left.representations == mirrored && left.hotSpot == CGPoint(x: 13, y: 3))
}

@Test func keepingFramesAppliesToLeftHandedImages() throws {
    var arrow = try cursor("com.apple.coregraphics.Arrow", frames: 4)
    let mirrored = arrow.useMirroredImagesAsLeftHanded()
    #expect(mirrored)
    let kept = try #require(arrow.keepingFrames([0, 2], frameDuration: 0.2))
    #expect(kept.leftHandedRepresentations.count == 2)
    #expect(kept.problems.isEmpty)
}

@Test func flagsLeftHandedImagesThatDontFit() throws {
    var arrow = try cursor("com.apple.coregraphics.Arrow")
    arrow.leftHandedRepresentations = [try sheet(side: 20, filled: 2)]
    #expect(arrow.problems.contains(.leftHandedImageDoesNotFit(CGSize(width: 20, height: 20))))
}

@Test func findsArrowLikeCursorsLeftUnmirrored() throws {
    // Kiriko style: the I-beam is an arrow with its hot spot at the top left.
    var cape = Cape(identifier: "test", name: "T", author: "", cursors: [
        try cursor("com.apple.coregraphics.Arrow"),
        try cursor("com.apple.coregraphics.IBeam", hotSpot: CGPoint(x: 1, y: 1)),
        try cursor("com.apple.cursor.7", hotSpot: CGPoint(x: 8, y: 8)),                  // crosshair: centred
    ])
    #expect(cape.unevenMirroring == ["com.apple.coregraphics.IBeam": .notMirroredLikeArrow])
    cape.cursors[1].mirrorForLeftHanded = true
    #expect(cape.unevenMirroring.isEmpty)
    // A variant takes its base's setting, as in the engine.
    cape.cursors.append(try cursor("com.apple.coregraphics.IBeamS", hotSpot: CGPoint(x: 1, y: 1)))
    #expect(cape.unevenMirroring.isEmpty)
    // Nothing to say when the arrow isn't mirrored either.
    cape.cursors[1].mirrorForLeftHanded = nil
    cape.cursors[0].mirrorForLeftHanded = false
    #expect(cape.unevenMirroring.isEmpty)
}
