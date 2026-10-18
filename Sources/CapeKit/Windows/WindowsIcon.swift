import CoreGraphics
import Foundation
import ImageIO

/// Errors while reading Windows cursor files.
public enum WindowsCursorError: Error, Equatable, LocalizedError {
    case notACursor
    case unsupportedImage(String)
    case noCursorsFound

    public var errorDescription: String? {
        switch self {
        case .notACursor: String(localized: "The file is not a Windows cursor (.cur or .ani).")
        case .unsupportedImage(let detail): String(localized: "A cursor image can't be read (\(detail)).")
        case .noCursorsFound: String(localized: "No Windows cursors were found.")
        }
    }
}

/// One image inside a Windows `.cur` or `.ico` file.
struct WindowsIconImage {
    let image: CGImage
    /// In pixels from the top-left corner (zero for `.ico` files).
    let hotSpot: CGPoint

    var width: Int { image.width }
}

/// Reads the ICO/CUR container: a directory of images, each a PNG or a headerless BMP (DIB).
enum WindowsIcon {
    static func images(from data: Data) throws -> [WindowsIconImage] {
        var reader = ByteReader(data)
        guard try reader.u16() == 0 else { throw WindowsCursorError.notACursor }
        let type = try reader.u16()                 // 1 = icon, 2 = cursor
        let count = Int(try reader.u16())
        guard type == 1 || type == 2, count > 0 else { throw WindowsCursorError.notACursor }

        var images: [WindowsIconImage] = []
        for _ in 0..<count {
            _ = try reader.u8()                      // width (0 means 256)
            _ = try reader.u8()                      // height
            _ = try reader.u8()                      // palette size
            _ = try reader.u8()                      // reserved
            let x = try reader.u16()                 // cursors: hot spot; icons: planes
            let y = try reader.u16()                 // cursors: hot spot; icons: bit count
            let size = Int(try reader.u32())
            let offset = Int(try reader.u32())
            guard offset >= 0, size > 0, offset + size <= data.count else { throw WindowsCursorError.notACursor }
            let payload = data.subdata(in: data.startIndex + offset ..< data.startIndex + offset + size)
            let image = try decodeImage(payload)
            let hotSpot = type == 2 ? CGPoint(x: Int(x), y: Int(y)) : .zero
            images.append(WindowsIconImage(image: image, hotSpot: hotSpot))
        }
        return images
    }

    private static func decodeImage(_ payload: Data) throws -> CGImage {
        if payload.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            guard let source = CGImageSourceCreateWithData(payload as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw WindowsCursorError.unsupportedImage("PNG")
            }
            return image
        }
        return try DIBDecoder.decode(payload)
    }
}

/// Decodes the bitmap of an icon entry: a BITMAPINFOHEADER, an optional palette, the colour
/// bitmap and a 1-bit transparency mask, both stored bottom-up.
enum DIBDecoder {
    static func decode(_ data: Data) throws -> CGImage {
        var reader = ByteReader(data)
        let headerSize = Int(try reader.u32())
        let width = Int(try reader.i32())
        let doubledHeight = Int(try reader.i32())
        _ = try reader.u16()                         // planes
        let bitCount = Int(try reader.u16())
        let compression = try reader.u32()
        _ = try reader.u32()                         // image size
        _ = try reader.u32()                         // x pixels per metre
        _ = try reader.u32()                         // y pixels per metre
        let usedColours = Int(try reader.u32())
        let height = abs(doubledHeight) / 2          // colour bitmap + mask
        guard headerSize >= 40, width > 0, height > 0, width <= 1024, height <= 1024 else {
            throw WindowsCursorError.unsupportedImage("bitmap header")
        }
        guard [1, 4, 8, 16, 24, 32].contains(bitCount) else {
            throw WindowsCursorError.unsupportedImage("\(bitCount)-bit bitmap")
        }
        guard compression == 0 || compression == 3 else {
            throw WindowsCursorError.unsupportedImage("compressed bitmap")
        }

        reader.position = headerSize
        if compression == 3 && headerSize == 40 { reader.position += 12 }     // bit field masks

        var palette: [(r: UInt8, g: UInt8, b: UInt8)] = []
        if bitCount <= 8 {
            let entries = usedColours > 0 ? usedColours : 1 << bitCount
            for _ in 0..<entries {
                let b = try reader.u8(), g = try reader.u8(), r = try reader.u8()
                _ = try reader.u8()
                palette.append((r, g, b))
            }
        }

        let colourStride = ((width * bitCount + 31) / 32) * 4
        let maskStride = ((width + 31) / 32) * 4
        let colourStart = reader.position
        let maskStart = colourStart + colourStride * height
        guard colourStart + colourStride * height <= data.count else {
            throw WindowsCursorError.unsupportedImage("truncated bitmap")
        }
        let hasMask = maskStart + maskStride * height <= data.count
        let bytes = [UInt8](data)

        func maskBit(_ x: Int, _ row: Int) -> Bool {
            guard hasMask else { return false }
            let byte = bytes[maskStart + row * maskStride + x / 8]
            return byte & (0x80 >> UInt8(x % 8)) != 0
        }

        // RGBA, top-down, not premultiplied.
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var anyAlpha = false
        for row in 0..<height {
            let source = colourStart + row * colourStride
            let target = (height - 1 - row) * width * 4                   // bottom-up → top-down
            for x in 0..<width {
                var r: UInt8 = 0, g: UInt8 = 0, b: UInt8 = 0, a: UInt8 = 255
                switch bitCount {
                case 32:
                    let p = source + x * 4
                    b = bytes[p]; g = bytes[p + 1]; r = bytes[p + 2]; a = bytes[p + 3]
                    if a != 0 { anyAlpha = true }
                case 24:
                    let p = source + x * 3
                    b = bytes[p]; g = bytes[p + 1]; r = bytes[p + 2]
                case 16:
                    let value = UInt16(bytes[source + x * 2]) | UInt16(bytes[source + x * 2 + 1]) << 8
                    r = UInt8((value >> 10) & 0x1F) << 3
                    g = UInt8((value >> 5) & 0x1F) << 3
                    b = UInt8(value & 0x1F) << 3
                default:
                    let bitOffset = x * bitCount
                    let byte = bytes[source + bitOffset / 8]
                    let shift = 8 - bitCount - bitOffset % 8
                    let index = Int((byte >> UInt8(shift)) & UInt8((1 << bitCount) - 1))
                    if index < palette.count { (r, g, b) = palette[index] }
                }
                let t = target + x * 4
                pixels[t] = r; pixels[t + 1] = g; pixels[t + 2] = b; pixels[t + 3] = a
            }
        }

        // Without real alpha the mask decides: set bits are transparent. (A set mask bit
        // over a non-black pixel means "invert the screen" on Windows, which macOS cursors
        // can't do; those pixels are drawn black.)
        if bitCount != 32 || !anyAlpha {
            for row in 0..<height {
                for x in 0..<width {
                    let t = ((height - 1 - row) * width + x) * 4
                    if maskBit(x, row) {
                        let inverts = pixels[t] != 0 || pixels[t + 1] != 0 || pixels[t + 2] != 0
                        if inverts {
                            pixels[t] = 0; pixels[t + 1] = 0; pixels[t + 2] = 0; pixels[t + 3] = 255
                        } else {
                            pixels[t + 3] = 0
                        }
                    } else {
                        pixels[t + 3] = 255
                    }
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true,
                                  intent: .defaultIntent) else {
            throw WindowsCursorError.unsupportedImage("bitmap")
        }
        return image
    }
}

/// Little-endian reading with bounds checks.
struct ByteReader {
    let bytes: [UInt8]
    var position = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    var remaining: Int { bytes.count - position }

    mutating func u8() throws -> UInt8 {
        guard position < bytes.count else { throw WindowsCursorError.notACursor }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func u16() throws -> UInt16 {
        UInt16(try u8()) | UInt16(try u8()) << 8
    }

    mutating func u32() throws -> UInt32 {
        UInt32(try u16()) | UInt32(try u16()) << 16
    }

    mutating func i32() throws -> Int32 {
        Int32(bitPattern: try u32())
    }

    mutating func tag() throws -> String {
        let chars = try (0..<4).map { _ in try u8() }
        return String(decoding: chars, as: UTF8.self)
    }

    mutating func data(count: Int) throws -> Data {
        guard count >= 0, position + count <= bytes.count else { throw WindowsCursorError.notACursor }
        defer { position += count }
        return Data(bytes[position ..< position + count])
    }
}
