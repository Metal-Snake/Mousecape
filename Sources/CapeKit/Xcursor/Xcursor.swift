import CoreGraphics
import Foundation

/// Errors while reading Xcursor files (the cursor format of X11 and Wayland desktops).
public enum XcursorError: Error, Equatable, LocalizedError {
    case notACursor
    case noCursorsFound

    public var errorDescription: String? {
        switch self {
        case .notACursor: String(localized: "The file is not an Xcursor file.")
        case .noCursorsFound: String(localized: "No Xcursor files were found.")
        }
    }
}

/// One image inside an Xcursor file.
struct XcursorImage {
    /// The size the image is meant for (`Xcursor.defaultSize` at the default pointer size).
    let nominalSize: Int
    let image: CGImage
    /// In pixels from the top-left corner.
    let hotSpot: CGPoint
    /// How long this frame shows, in milliseconds (animated cursors only).
    let delay: Int
}

/// Reads Xcursor files: a table of contents pointing to image chunks, each with its nominal
/// size, hot spot, frame delay and premultiplied ARGB pixels (see `man Xcursor`). An
/// animated cursor has several images of the same nominal size, in display order.
public enum Xcursor {
    /// The default pointer size on Linux desktops (`XCURSOR_SIZE`). Measured against Apple's
    /// cursors, a theme's 24-pixel images match macOS's default size in points.
    public static let defaultSize = 24

    private static let magic = Array("Xcur".utf8)
    private static let imageType: UInt32 = 0xFFFD_0002

    /// Whether `data` starts like an Xcursor file.
    public static func isXcursor(_ data: Data) -> Bool {
        data.starts(with: magic)
    }

    /// Whether the file at `url` is an Xcursor file (reads only its first bytes).
    public static func isXcursorFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: magic.count)).map(isXcursor) ?? false
    }

    static func images(from data: Data) throws -> [XcursorImage] {
        guard isXcursor(data) else { throw XcursorError.notACursor }
        do {
            return try readImages(from: data)
        } catch is WindowsCursorError {                             // ByteReader ran past the end
            throw XcursorError.notACursor
        }
    }

    private static func readImages(from data: Data) throws -> [XcursorImage] {
        var reader = ByteReader(data)
        reader.position = 4
        let headerSize = Int(try reader.u32())
        _ = try reader.u32()                                        // file version
        let entryCount = Int(try reader.u32())
        guard headerSize >= 16, entryCount <= 4096 else { throw XcursorError.notACursor }
        reader.position = headerSize

        var images: [XcursorImage] = []
        for _ in 0..<entryCount {
            let type = try reader.u32()
            _ = try reader.u32()                                    // subtype: the nominal size
            let position = Int(try reader.u32())
            guard type == imageType else { continue }               // comments
            let next = reader.position
            images.append(try image(in: data, at: position))
            reader.position = next
        }
        guard !images.isEmpty else { throw XcursorError.notACursor }
        return images
    }

    private static func image(in data: Data, at position: Int) throws -> XcursorImage {
        var reader = ByteReader(data)
        guard position >= 0, position < reader.bytes.count else { throw XcursorError.notACursor }
        reader.position = position
        let headerSize = Int(try reader.u32())
        guard try reader.u32() == imageType else { throw XcursorError.notACursor }
        let nominalSize = Int(try reader.u32())
        _ = try reader.u32()                                        // chunk version
        let width = Int(try reader.u32()), height = Int(try reader.u32())
        let hotX = Int(try reader.u32()), hotY = Int(try reader.u32())
        let delay = Int(try reader.u32())
        guard headerSize >= 36, width > 0, height > 0, width <= 1024, height <= 1024 else {
            throw XcursorError.notACursor
        }
        reader.position = position + headerSize
        // Little-endian ARGB words, premultiplied: in memory B, G, R, A.
        let pixels = try reader.data(count: width * height * 4)
        guard let provider = CGDataProvider(data: pixels as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                                                           | CGImageAlphaInfo.premultipliedFirst.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw XcursorError.notACursor }
        return XcursorImage(nominalSize: nominalSize, image: image,
                            hotSpot: CGPoint(x: min(hotX, width), y: min(hotY, height)), delay: delay)
    }

    /// A cape cursor for `identifier` from the contents of an Xcursor file.
    ///
    /// Like libXcursor on Linux, the images whose nominal size is closest to `defaultSize`
    /// are shown at their own pixel size, one pixel per point: a theme made only at size 48
    /// shows its 48-pixel images unscaled there, so scaling them down to 24 points would
    /// make the cursor half as large as on Linux. Higher scales take the file's images of a
    /// multiple of that size when it has them (else the next larger ones, scaled down);
    /// scales larger than the file's largest images are left out.
    public static func capeCursor(from data: Data, identifier: String) throws -> CapeCursor {
        let all = try images(from: data)
        // Images by nominal size, frames in file order.
        var bySize: [Int: [XcursorImage]] = [:]
        for image in all { bySize[image.nominalSize, default: []].append(image) }
        // The first size in the file among the closest, as libXcursor picks it.
        guard let baseSize = all.map(\.nominalSize).min(by: { abs($0 - defaultSize) < abs($1 - defaultSize) }),
              let base = bySize[baseSize], let reference = base.first,
              let largestSize = bySize.keys.max() else {
            throw XcursorError.notACursor
        }

        let pointWidth = reference.image.width, pointHeight = reference.image.height
        let timing = CursorSheet.timeline(steps: Array(base.indices),
                                          durations: base.map { max($0.delay, 1) }, unit: 0.001)

        var representations: [Data] = []
        for scale in CapeCursor.supportedScales where scale == 1 || baseSize * scale <= largestSize {
            // The smallest size at least as large as needed, with the same frames.
            let source = scale == 1 ? base : bySize.keys.sorted()
                .first { $0 >= baseSize * scale && bySize[$0]!.count == base.count }
                .map { bySize[$0]! } ?? base
            guard let sheet = CursorSheet.render(timing.frames.map { source[$0].image },
                                                 frameWidth: pointWidth * scale, frameHeight: pointHeight * scale) else {
                throw XcursorError.notACursor
            }
            representations.append(sheet)
        }
        return CapeCursor(identifier: identifier, frameCount: timing.frames.count,
                          frameDuration: base.count > 1 ? timing.duration : 1,
                          hotSpot: reference.hotSpot, size: CGSize(width: pointWidth, height: pointHeight),
                          representations: representations)
    }
}
