import AppKit
import ImageIO

/// Editing support: building capes from images and checking that they will apply.

extension CapeCursor {
    /// The pixel densities a cape can carry (the original editor's 1x, 2x, 5x and 10x wells).
    public static let supportedScales = [1, 2, 5, 10]

    /// The window server refuses more frames than this.
    public static let maximumFrameCount = 24

    /// Frames left when applying a longer animation: the engine keeps every n-th frame.
    public static func reducedFrameCount(_ frameCount: Int) -> Int {
        guard frameCount > maximumFrameCount else { return frameCount }
        let step = (frameCount + maximumFrameCount - 1) / maximumFrameCount
        return (frameCount + step - 1) / step
    }

    /// A copy within the frame limit, the same way the engine reduces it when applying:
    /// every n-th frame is kept and shown n times as long, so the animation keeps its
    /// speed. Returns the cursor unchanged when it is within the limit, nil if an image
    /// can't be decoded.
    public func reducingFrames() -> CapeCursor? {
        guard frameCount > Self.maximumFrameCount else { return self }
        let kept = FrameSelection.everyNth(of: frameCount)
        return keepingFrames(kept, frameDuration: FrameSelection.loopPreservingDuration(
            frameDuration: frameDuration, frameCount: frameCount, kept: kept.count))
    }

    /// A copy with only the given frames (0-based, in the order given), each shown for
    /// `frameDuration`. Nil if an index is out of range or an image can't be decoded.
    public func keepingFrames(_ indices: [Int], frameDuration: Double) -> CapeCursor? {
        guard !indices.isEmpty, indices.allSatisfy({ (0..<frameCount).contains($0) }),
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let count = indices.count

        var rebuilt: [Data] = []
        for data in representations {
            guard let sheet = NSBitmapImageRep(data: data)?.cgImage else { return nil }
            let frameHeight = sheet.height / frameCount
            guard frameHeight > 0,
                  let context = CGContext(data: nil, width: sheet.width, height: frameHeight * count,
                                          bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            for (slot, index) in indices.enumerated() {
                // Cropping counts from the top, drawing from the bottom.
                guard let frame = sheet.cropping(to: CGRect(x: 0, y: index * frameHeight,
                                                            width: sheet.width, height: frameHeight)) else { return nil }
                context.draw(frame, in: CGRect(x: 0, y: (count - 1 - slot) * frameHeight,
                                               width: sheet.width, height: frameHeight))
            }
            guard let image = context.makeImage(),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
            rebuilt.append(png)
        }
        var copy = self
        copy.representations = rebuilt
        copy.frameCount = count
        copy.frameDuration = frameDuration
        return copy
    }

    /// The representation whose width matches `scale` times the point width.
    public func representation(for scale: Int) -> Data? {
        representations.first { Self.scale(of: $0, pointWidth: size.width) == scale }
    }

    /// Replaces (or with nil removes) the representation at `scale`.
    public mutating func setRepresentation(_ data: Data?, for scale: Int) {
        representations.removeAll { Self.scale(of: $0, pointWidth: size.width) == scale }
        if let data { representations.append(data) }
        representations.sort { Self.pixelWidth(of: $0) < Self.pixelWidth(of: $1) }
    }

    /// Pixel size a sheet at `scale` must have: one frame wide, all frames high.
    public func expectedPixelSize(for scale: Int) -> CGSize {
        CGSize(width: size.width * Double(scale), height: size.height * Double(scale) * Double(frameCount))
    }

    /// Everything that would stop this cursor from applying, or make it look wrong.
    public var problems: [CursorProblem] {
        var problems: [CursorProblem] = []
        if representations.isEmpty { problems.append(.noImages) }
        if frameCount < 1 { problems.append(.frameCountOutOfRange) }
        if frameCount > Self.maximumFrameCount {
            problems.append(.framesWillBeReduced(from: frameCount, to: Self.reducedFrameCount(frameCount)))
        }
        if hotSpot.x < 0 || hotSpot.y < 0 || hotSpot.x > size.width || hotSpot.y > size.height {
            problems.append(.hotSpotOutside)
        }
        for data in representations {
            guard let pixels = Self.pixelSize(of: data) else {
                problems.append(.unreadableImage)
                continue
            }
            let scale = Double(pixels.width) / size.width
            let expectedHeight = size.height * scale * Double(frameCount)
            if scale.rounded() != scale || !Self.supportedScales.contains(Int(scale)) {
                problems.append(.unexpectedWidth(pixels))
            } else if abs(Double(pixels.height) - expectedHeight) > 0.5 {
                problems.append(.heightDoesNotMatchFrames(pixels, expected: Int(expectedHeight)))
            }
        }
        return problems
    }

    /// Image data from any format NSImage reads, as PNG in sRGB (what the engine expects).
    /// Nil if the data is not an image.
    public static func normalizedPNG(from imageData: Data) -> (png: Data, pixelSize: CGSize)? {
        guard let rep = NSBitmapImageRep(data: imageData) else { return nil }
        let target: NSColorSpace = rep.colorSpace.numberOfColorComponents == 1 ? .genericGamma22Gray : .sRGB
        let tagged = rep.retagging(with: target) ?? rep
        guard let png = tagged.representation(using: .png, properties: [:]) else { return nil }
        return (png, CGSize(width: rep.pixelsWide, height: rep.pixelsHigh))
    }

    /// Read from the image header, without decoding the pixels.
    static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: width, height: height)
    }

    static func pixelWidth(of data: Data) -> Int {
        Int(pixelSize(of: data)?.width ?? 0)
    }

    static func scale(of data: Data, pointWidth: Double) -> Int? {
        guard pointWidth > 0 else { return nil }
        let scale = Double(pixelWidth(of: data)) / pointWidth
        return scale.rounded() == scale ? Int(scale) : nil
    }
}

public enum CursorProblem: Equatable, Sendable, CustomStringConvertible {
    case noImages
    case frameCountOutOfRange
    case framesWillBeReduced(from: Int, to: Int)
    case hotSpotOutside
    case unreadableImage
    case unexpectedWidth(CGSize)
    case heightDoesNotMatchFrames(CGSize, expected: Int)

    /// True when the cursor won't apply or will look wrong; false for things macOS works
    /// around (a reduced animation, a hot spot off the image).
    public var isError: Bool {
        switch self {
        case .framesWillBeReduced, .hotSpotOutside: false
        default: true
        }
    }

    public var description: String {
        switch self {
        case .noImages:
            String(localized: "No images yet.")
        case .frameCountOutOfRange:
            String(localized: "A cursor needs at least one frame.")
        case .framesWillBeReduced(let from, let to):
            String(localized: "macOS shows at most \(CapeCursor.maximumFrameCount) frames; the \(from) frames are reduced to \(to) when applied.")
        case .hotSpotOutside:
            String(localized: "The hot spot lies outside the cursor.")
        case .unreadableImage:
            String(localized: "An image cannot be read.")
        case .unexpectedWidth(let px):
            String(localized: "An image is \(Int(px.width)) px wide, which is not 1, 2, 5 or 10 times the cursor width.")
        case .heightDoesNotMatchFrames(let px, let expected):
            String(localized: "An image is \(Int(px.height)) px high; the frames need \(expected) px.")
        }
    }
}

extension Cape {
    /// A new, empty cape with an identifier unique enough for a local library.
    public static func untitled(author: String) -> Cape {
        let slug = author.lowercased().filter { $0.isLetter || $0.isNumber }
        let stamp = Int(Date().timeIntervalSince1970)
        return Cape(identifier: "local.\(slug.isEmpty ? "user" : slug).untitled.\(stamp)",
                    name: String(localized: "Untitled"), author: author)
    }

    /// System cursors this cape does not replace yet, in display order.
    public var missingCursorIdentifiers: [String] {
        let used = Set(cursors.map(\.identifier))
        return CursorNames.all.keys
            .filter { !used.contains($0) }
            .sorted {
                let ra = CursorNames.rank(of: $0), rb = CursorNames.rank(of: $1)
                if ra != rb { return ra < rb }
                return CursorNames.name(for: $0).localizedStandardCompare(CursorNames.name(for: $1)) == .orderedAscending
            }
    }

    /// Adds an empty cursor for a system identifier (32 × 32 points, hot spot top left).
    @discardableResult
    public mutating func addCursor(identifier: String) -> CapeCursor {
        let cursor = CapeCursor(identifier: identifier, size: CGSize(width: 32, height: 32), representations: [])
        cursors.append(cursor)
        cursors.sort(by: CapeCursor.displayOrder)
        return cursor
    }

    public mutating func removeCursor(identifier: String) {
        cursors.removeAll { $0.identifier == identifier }
    }

    /// Problems per cursor identifier, only for cursors that have any.
    public var problems: [String: [CursorProblem]] {
        Dictionary(uniqueKeysWithValues: cursors.compactMap { cursor in
            let problems = cursor.problems
            return problems.isEmpty ? nil : (cursor.identifier, problems)
        })
    }
}

/// Ways to pick the frames of an animation that has more than macOS shows.
public enum FrameSelection {
    /// Every n-th frame, n as small as possible to stay within the limit (what the engine
    /// does when applying).
    public static func everyNth(of frameCount: Int, limit: Int = CapeCursor.maximumFrameCount) -> [Int] {
        let step = max(1, (frameCount + limit - 1) / limit)
        return Array(stride(from: 0, to: frameCount, by: step))
    }

    /// `count` frames spread as evenly as possible over the whole animation.
    public static func spread(of frameCount: Int, count: Int = CapeCursor.maximumFrameCount) -> [Int] {
        guard count < frameCount else { return Array(0..<frameCount) }
        return (0..<count).map { Int((Double($0) * Double(frameCount) / Double(count)).rounded(.down)) }
    }

    /// The first `count` frames.
    public static func first(of frameCount: Int, count: Int = CapeCursor.maximumFrameCount) -> [Int] {
        Array(0..<min(count, frameCount))
    }

    /// Duration per frame that keeps one loop as long as the original.
    public static func loopPreservingDuration(frameDuration: Double, frameCount: Int, kept: Int) -> Double {
        guard kept > 0 else { return frameDuration }
        return frameDuration * Double(frameCount) / Double(kept)
    }

    /// Whether the kept frames are unevenly spaced (counting the wrap back to the start).
    /// With one duration for all frames, uneven gaps make steady motion stutter.
    public static func isUneven(_ indices: [Int], frameCount: Int) -> Bool {
        let sorted = indices.sorted()
        guard sorted.count > 1 else { return false }
        var gaps = zip(sorted, sorted.dropFirst()).map { $1 - $0 }
        gaps.append(sorted[0] + frameCount - sorted[sorted.count - 1])
        return Set(gaps).count > 1
    }
}
