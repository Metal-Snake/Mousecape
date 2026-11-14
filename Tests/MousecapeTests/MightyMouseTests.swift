import AppKit
import Testing
import TestSupport
import MousecloakCore

/// The engine converts MightyMouse files on import. They are untrusted input: a broken entry
/// is skipped, and nothing in one may make the engine read past its data or crash.

private let arrow = "com.apple.coregraphics.Arrow"

private func convert(_ theme: Any) -> [String: Any]? {
    let metadata: [String: Any] = ["name": "Test", "version": 1.0, "author": "Tester",
                                   "identifier": "local.test.mightymouse"]
    return createCapeFromMightyMouse(theme as? [AnyHashable: Any], metadata) as? [String: Any]
}

private func cursors(_ cape: [String: Any]?) -> [String: [String: Any]] {
    cape?["Cursors"] as? [String: [String: Any]] ?? [:]
}

@Test func convertsAMightyMouseCursor() throws {
    let cape = convert(mightyMouseTheme(cursors: [arrow: mightyMouseEntry(frames: 2)]))
    let cursor = try #require(cursors(cape)[arrow])
    #expect(cursor["FrameCount"] as? Int == 2)
    #expect(cursor["HotSpotX"] as? Double == 1)
    let image = try #require((cursor["Representations"] as? [Data])?.first.flatMap(NSBitmapImageRep.init(data:)))
    #expect(image.pixelsWide == 16 && image.pixelsHigh == 32)
    #expect(image.colorAt(x: 8, y: 8)?.redComponent ?? 0 > 0.9)
}

/// An entry that describes more pixels than its data has, or values of the wrong type or
/// out of range.
private func brokenEntry(_ name: String) -> [String: Any] {
    var e = mightyMouseEntry()
    switch name {
    case "data one byte short": e["CursorData"] = (e["CursorData"] as! Data).dropLast()
    case "no data": e["CursorData"] = Data()
    case "data as a string": e["CursorData"] = "pixels"
    case "more rows than data": e["PixelsHigh"] = 1_000
    case "more frames than data": e["FrameCount"] = 3
    case "rows too short for the width": e["BytesPerRow"] = 4
    case "huge size": e["PixelsWide"] = Int.max / 2; e["PixelsHigh"] = Int.max / 2
    case "size over the pixel limit": e["PixelsWide"] = 100_000; e["PixelsHigh"] = 100_000
    case "negative width": e["PixelsWide"] = -16
    case "zero frames": e["FrameCount"] = 0
    case "fractional width": e["PixelsWide"] = 15.5
    case "width as a string": e["PixelsWide"] = "16"
    case "impossible pixel format": e["SamplesPerPixel"] = 5; e["BitsPerPixel"] = 7
    case "hot spot as a string": e["HotspotX"] = "1"
    default: Issue.record("unknown case \(name)")
    }
    return e
}

/// The broken cursor is left out; a good one next to it still converts.
@Test(arguments: ["data one byte short", "no data", "data as a string", "more rows than data",
                  "more frames than data", "rows too short for the width", "huge size",
                  "size over the pixel limit", "negative width", "zero frames", "fractional width",
                  "width as a string", "impossible pixel format", "hot spot as a string"])
func skipsABrokenCursor(_ name: String) {
    let theme = mightyMouseTheme(cursors: [arrow: brokenEntry(name), "com.apple.coregraphics.IBeam": mightyMouseEntry()])
    #expect(Set(cursors(convert(theme)).keys) == ["com.apple.coregraphics.IBeam"])
}

/// A file whose structure is wrong.
private func brokenFile(_ name: String) -> [String: Any] {
    switch name {
    case "cursors as an array": return ["Cursors": ["Global", "Cursor Data"]]
    case "global as a string": return ["Cursors": ["Global": "x", "Cursor Data": [String: Any]()]]
    case "identifiers as an array":
        return ["Cursors": ["Global": ["Identifiers": ["a", "b"]], "Cursor Data": [String: Any]()]]
    case "entry as a string":
        return ["Cursors": ["Global": ["Identifiers": [arrow: "key"]], "Cursor Data": [String: Any]()]]
    case "custom key as a number":
        return ["Cursors": ["Global": ["Identifiers": [arrow: ["Custom Key": 7]]], "Cursor Data": ["7": mightyMouseEntry()]]]
    case "cursor data as a string":
        return ["Cursors": ["Global": ["Identifiers": [arrow: ["Custom Key": "k"]]], "Cursor Data": ["k": "entry"]]]
    default: Issue.record("unknown case \(name)"); return [:]
    }
}

/// It is refused as a whole, without a crash.
@Test(arguments: ["cursors as an array", "global as a string", "identifiers as an array",
                  "entry as a string", "custom key as a number", "cursor data as a string"])
func refusesABrokenFile(_ name: String) {
    #expect(convert(brokenFile(name)) == nil)
}
