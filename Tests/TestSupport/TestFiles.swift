import AppKit
import CoreGraphics

// Builders for the files the tests feed the importers and editing tools: images, sprite
// sheets, Windows cursors, Xcursor files. Shared by the test targets.

/// A PNG of `width` × `height` pixels (sRGB, transparent), drawn by `draw` with the origin
/// at the bottom left as usual in Core Graphics.
public func pngImage(width: Int, height: Int, draw: (CGContext) -> Void = { _ in }) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(context)
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

/// Little-endian bytes.
public struct Bytes {
    public var data = Data()
    public init() {}
    public mutating func u8(_ v: Int) { data.append(UInt8(v & 0xFF)) }
    public mutating func u16(_ v: Int) { u8(v); u8(v >> 8) }
    public mutating func u32(_ v: Int) { u16(v & 0xFFFF); u16(v >> 16) }
    public mutating func tag(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
}

/// A `.cur` file with the given images (PNG or DIB payloads, each with its size and hot spot).
public func curFile(_ images: [(payload: Data, size: Int, hotSpot: (Int, Int))]) -> Data {
    var b = Bytes()
    b.u16(0); b.u16(2); b.u16(images.count)
    var offset = 6 + 16 * images.count
    for image in images {
        b.u8(image.size % 256); b.u8(image.size % 256); b.u8(0); b.u8(0)
        b.u16(image.hotSpot.0); b.u16(image.hotSpot.1)
        b.u32(image.payload.count); b.u32(offset)
        offset += image.payload.count
    }
    for image in images { b.data.append(image.payload) }
    return b.data
}

/// One image chunk of an Xcursor file: a solid colour (premultiplied ARGB) at a nominal size.
public struct XcursorTestImage {
    public var nominalSize: Int
    public var width: Int
    public var height: Int
    public var hotSpot: (Int, Int)
    public var delay: Int
    public var argb: UInt32

    public init(nominalSize: Int, width: Int, height: Int, hotSpot: (Int, Int), delay: Int = 0,
                argb: UInt32 = 0xFF_FF_00_00) {                      // opaque red
        self.nominalSize = nominalSize
        self.width = width
        self.height = height
        self.hotSpot = hotSpot
        self.delay = delay
        self.argb = argb
    }
}

/// An Xcursor file with the given images, in order, plus a comment chunk to skip.
public func xcursorFile(_ images: [XcursorTestImage]) -> Data {
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

/// A MaCursor theme (`.cursor`): a property list like a cape's under MaCursor's own names.
/// `cursors` maps identifiers to cape-style cursor entries; nil leaves a key out.
public func maCursorFile(name: String? = "Test Theme", creator: String? = "Tester", version: Double = 2,
                         cursors: [String: Any], format: PropertyListSerialization.PropertyListFormat = .xml) -> Data {
    var theme: [String: Any] = ["Identifier": "TestTheme", "HiDPI": true, "ThemeVersion": version,
                                "UUID": "114EDCB9-0C84-47D3-BEB2-FF199399DE59", "Cursors": cursors]
    theme["ThemeName"] = name
    theme["Creator"] = creator
    return try! PropertyListSerialization.data(fromPropertyList: theme, format: format, options: 0)
}

/// A cape-style cursor entry with one sprite sheet per scale (1x and 2x) of `frames` frames.
public func maCursorEntry(points: Int = 32, frames: Int = 1, hotSpot: (Double, Double) = (4, 2)) -> [String: Any] {
    ["FrameCount": frames, "FrameDuration": 0.05, "HotSpotX": hotSpot.0, "HotSpotY": hotSpot.1,
     "PointsWide": Double(points), "PointsHigh": Double(points),
     "Representations": [pngImage(width: points, height: points * frames),
                         pngImage(width: points * 2, height: points * 2 * frames)]]
}

/// A MightyMouse theme as its property list: `Cursors` → `Global` → `Identifiers` names each
/// cursor's entry in `Cursor Data`. `cursors` maps identifiers to such entries.
public func mightyMouseTheme(cursors: [String: [String: Any]]) -> [String: Any] {
    var identifiers: [String: Any] = [:]
    var data: [String: Any] = [:]
    for (index, (identifier, entry)) in cursors.sorted(by: { $0.key < $1.key }).enumerated() {
        identifiers[identifier] = ["Custom Key": "cursor\(index)"]
        data["cursor\(index)"] = entry
    }
    return ["Cursors": ["Global": ["Identifiers": identifiers], "Cursor Data": data]]
}

/// A MightyMouse cursor entry: raw 32-bit ARGB rows, all frames stacked, opaque red.
/// `dataBytes` cuts or pads the raw data to that length.
public func mightyMouseEntry(width: Int = 16, height: Int = 16, frames: Int = 1,
                             dataBytes: Int? = nil) -> [String: Any] {
    var pixels = Data(count: width * height * frames * 4)
    for i in stride(from: 0, to: pixels.count, by: 4) { pixels[i] = 0xFF; pixels[i + 1] = 0xFF }
    if let dataBytes { pixels = Data(pixels.prefix(dataBytes)) + Data(count: max(0, dataBytes - pixels.count)) }
    return ["BitsPerPixel": 32, "BitsPerSample": 8, "SamplesPerPixel": 4, "BytesPerRow": width * 4,
            "PixelsWide": width, "PixelsHigh": height, "FrameCount": frames, "FrameDuration": 0.1,
            "HotspotX": 1.0, "HotspotY": 2.0, "CursorData": pixels]
}
