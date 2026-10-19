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
