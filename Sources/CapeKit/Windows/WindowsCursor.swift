import AppKit
import CoreGraphics

/// Turns Windows cursor files into cape cursors.
public enum WindowsCursor {
    /// Windows draws cursors at 32 × 32 pixels at the default pointer size, whatever size the
    /// file's images are; that becomes the cursor's point size here.
    public static let pointSize = 32

    /// A cape cursor for `identifier` from the contents of a `.cur`, `.ico` or `.ani` file.
    /// Images are resampled to 1x and 2x (and 5x when the source is large enough).
    public static func capeCursor(from data: Data, identifier: String) throws -> CapeCursor {
        let frames: [WindowsIconImage]
        var frameDuration = 1.0
        if data.starts(with: Array("RIFF".utf8)) {
            let animation = try WindowsAni.parse(data)
            let chosen = animation.frames.map(largest)
            let timing = timeline(steps: animation.steps, rates: animation.rates)
            frames = timing.frames.map { chosen[$0] }
            frameDuration = timing.duration
        } else {
            frames = [largest(try WindowsIcon.images(from: data))]
        }
        guard let first = frames.first else { throw WindowsCursorError.notACursor }

        let source = first.image
        let pointWidth = Double(pointSize)
        let pointHeight = (pointWidth * Double(source.height) / Double(source.width)).rounded()
        let toPoints = pointWidth / Double(source.width)
        let hotSpot = CGPoint(x: (first.hotSpot.x * toPoints).rounded(), y: (first.hotSpot.y * toPoints).rounded())

        // Every frame drawn into one sheet per scale. Scales above the source's own
        // resolution would only add blur.
        let scales = CapeCursor.supportedScales.filter { $0 == 1 || pointWidth * Double($0) <= Double(source.width) }
        var representations: [Data] = []
        for scale in scales {
            let width = Int(pointWidth) * scale, height = Int(pointHeight) * scale
            guard let sheet = renderSheet(frames.map(\.image), frameWidth: width, frameHeight: height) else {
                throw WindowsCursorError.unsupportedImage("resampling")
            }
            representations.append(sheet)
        }
        return CapeCursor(identifier: identifier, frameCount: frames.count, frameDuration: frameDuration,
                          hotSpot: hotSpot, size: CGSize(width: pointWidth, height: pointHeight),
                          representations: representations)
    }

    /// The sharpest image of a frame (files often carry 32, 48, 64 … pixel versions).
    private static func largest(_ images: [WindowsIconImage]) -> WindowsIconImage {
        images.max { $0.width < $1.width } ?? images[0]
    }

    /// Frames in display order and one duration for all of them. Windows can give each step
    /// its own duration; here steps are repeated in units of the common divisor of their
    /// durations, as long as that stays within the frame limit, and otherwise they get the
    /// average duration.
    static func timeline(steps: [Int], rates: [Int]) -> (frames: [Int], duration: Double) {
        let jiffy = 1.0 / 60
        guard let firstRate = rates.first else { return (steps, jiffy) }
        if rates.allSatisfy({ $0 == firstRate }) {
            return (steps, Double(firstRate) * jiffy)
        }
        let unit = rates.reduce(0, gcd)
        let expanded = zip(steps, rates).flatMap { step, rate in Array(repeating: step, count: rate / unit) }
        if unit > 0, expanded.count <= CapeCursor.maximumFrameCount {
            return (expanded, Double(unit) * jiffy)
        }
        let average = Double(rates.reduce(0, +)) / Double(rates.count)
        return (steps, average * jiffy)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }

    /// Frames scaled into one vertical PNG sheet, first frame on top.
    private static func renderSheet(_ images: [CGImage], frameWidth: Int, frameHeight: Int) -> Data? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: frameWidth, height: frameHeight * images.count,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        for (index, image) in images.enumerated() {
            let y = (images.count - 1 - index) * frameHeight          // drawing counts from the bottom
            context.draw(image, in: CGRect(x: 0, y: y, width: frameWidth, height: frameHeight))
        }
        guard let sheet = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: sheet).representation(using: .png, properties: [:])
    }
}
