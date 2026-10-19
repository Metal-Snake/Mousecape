import AppKit
import CoreGraphics
import ImageIO

/// Sprite sheets: one image holding all frames of a cursor stacked vertically, first frame
/// on top. Decoding, slicing and drawing them, and turning frames with their own durations
/// into one animation; shared by the cursor model, the editing tools and the importers.
public enum CursorSheet {
    /// The most pixels a sheet may have to be decoded: a 10x sheet of a 64-point cursor with
    /// 120 frames. Real capes stay far below; a larger image in a file only eats memory.
    public static let maximumPixels = 640 * 640 * 120

    /// Width and height of an image, read from its header without decoding it.
    public static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: width, height: height)
    }

    /// The image in `data`; nil if it can't be read or is larger than `maximumPixels`.
    public static func decode(_ data: Data) -> CGImage? {
        guard let size = pixelSize(of: data), size.width * size.height <= Double(maximumPixels) else { return nil }
        return NSBitmapImageRep(data: data)?.cgImage
    }

    /// The `count` frames of a sheet, top to bottom; empty if it can't hold that many.
    public static func frames(of sheet: CGImage, count: Int) -> [CGImage] {
        guard count > 0, case let height = sheet.height / count, height > 0 else { return [] }
        return (0..<count).compactMap { index in
            sheet.cropping(to: CGRect(x: 0, y: index * height, width: sheet.width, height: height))
        }
    }

    /// An empty sRGB canvas with premultiplied alpha.
    static func context(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Frames scaled into one vertical PNG sheet, first frame on top.
    static func render(_ images: [CGImage], frameWidth: Int, frameHeight: Int) -> Data? {
        guard let context = context(width: frameWidth, height: frameHeight * images.count) else { return nil }
        context.interpolationQuality = .high
        for (index, image) in images.enumerated() {
            let y = (images.count - 1 - index) * frameHeight          // drawing counts from the bottom
            context.draw(image, in: CGRect(x: 0, y: y, width: frameWidth, height: frameHeight))
        }
        return context.makeImage().flatMap(png)
    }

    /// Each sheet in `sheets` (all with `frameCount` frames) rebuilt by `transform` from its
    /// frames, at the size of the frames `transform` returns; nil if one can't be read.
    static func rebuild(_ sheets: [Data], frameCount: Int, _ transform: ([CGImage]) -> [CGImage]?) -> [Data]? {
        var rebuilt: [Data] = []
        for data in sheets {
            guard let sheet = decode(data), case let frames = frames(of: sheet, count: frameCount),
                  frames.count == frameCount, let changed = transform(frames), let first = changed.first,
                  let png = render(changed, frameWidth: first.width, frameHeight: first.height) else { return nil }
            rebuilt.append(png)
        }
        return rebuilt
    }

    /// Frames in display order and one duration for all of them. Other formats can give
    /// each step its own duration (`durations`, in multiples of `unit` seconds); here steps
    /// are repeated in units of the common divisor of their durations, as long as that stays
    /// within the frame limit. Otherwise every step stays one frame with the average
    /// duration, and `stepDurations` keeps each step's own (for choosing frames by time).
    static func timeline(steps: [Int], durations: [Int], unit: Double)
        -> (frames: [Int], duration: Double, stepDurations: [Double]?) {
        guard let first = durations.first else { return (steps, unit, nil) }
        if durations.allSatisfy({ $0 == first }) {
            return (steps, Double(first) * unit, nil)
        }
        let divisor = durations.reduce(0, gcd)
        let expanded = zip(steps, durations).flatMap { step, duration in
            Array(repeating: step, count: duration / divisor)
        }
        if divisor > 0, expanded.count <= CapeCursor.maximumFrameCount {
            return (expanded, Double(divisor) * unit, nil)
        }
        let average = Double(durations.reduce(0, +)) / Double(durations.count)
        return (steps, average * unit, durations.map { Double($0) * unit })
    }

    static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}
