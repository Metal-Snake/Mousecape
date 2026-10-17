import AppKit

/// Editing support: building capes from images and checking that they will apply.

extension CapeCursor {
    /// The pixel densities a cape can carry (the original editor's 1x, 2x, 5x and 10x wells).
    public static let supportedScales = [1, 2, 5, 10]

    /// The window server refuses more frames than this.
    public static let maximumFrameCount = 24

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
        if !(1...Self.maximumFrameCount).contains(frameCount) { problems.append(.frameCountOutOfRange) }
        if hotSpot.x < 0 || hotSpot.y < 0 || hotSpot.x > size.width || hotSpot.y > size.height {
            problems.append(.hotSpotOutside)
        }
        for data in representations {
            guard let rep = NSBitmapImageRep(data: data) else {
                problems.append(.unreadableImage)
                continue
            }
            let pixels = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
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

    static func pixelWidth(of data: Data) -> Int {
        NSBitmapImageRep(data: data)?.pixelsWide ?? 0
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
    case hotSpotOutside
    case unreadableImage
    case unexpectedWidth(CGSize)
    case heightDoesNotMatchFrames(CGSize, expected: Int)

    public var description: String {
        switch self {
        case .noImages:
            String(localized: "No images yet.")
        case .frameCountOutOfRange:
            String(localized: "Frames must be between 1 and \(CapeCursor.maximumFrameCount).")
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
