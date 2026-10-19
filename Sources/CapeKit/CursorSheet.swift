import AppKit
import CoreGraphics

/// Helpers shared by the importers (Windows, Xcursor): turning frames with their own
/// durations into a cape animation, and drawing frames into a sprite sheet.
enum CursorSheet {
    /// Frames in display order and one duration for all of them. Other formats can give
    /// each step its own duration (`durations`, in multiples of `unit` seconds); here steps
    /// are repeated in units of the common divisor of their durations, as long as that stays
    /// within the frame limit, and otherwise they get the average duration.
    static func timeline(steps: [Int], durations: [Int], unit: Double) -> (frames: [Int], duration: Double) {
        guard let first = durations.first else { return (steps, unit) }
        if durations.allSatisfy({ $0 == first }) {
            return (steps, Double(first) * unit)
        }
        let divisor = durations.reduce(0, gcd)
        let expanded = zip(steps, durations).flatMap { step, duration in
            Array(repeating: step, count: duration / divisor)
        }
        if divisor > 0, expanded.count <= CapeCursor.maximumFrameCount {
            return (expanded, Double(divisor) * unit)
        }
        let average = Double(durations.reduce(0, +)) / Double(durations.count)
        return (steps, average * unit)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }

    /// Frames scaled into one vertical PNG sheet, first frame on top.
    static func render(_ images: [CGImage], frameWidth: Int, frameHeight: Int) -> Data? {
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
