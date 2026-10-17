import AppKit
import CoreGraphics

/// One cursor of a cape. Each representation is an image (PNG or TIFF data) holding all
/// frames stacked vertically, frame 0 at the top, at one pixel density (1x, 2x, 5x, 10x).
public struct CapeCursor: Identifiable, Equatable, Sendable {
    public var identifier: String
    public var frameCount: Int
    /// Seconds per frame.
    public var frameDuration: Double
    /// In points, from the top-left corner.
    public var hotSpot: CGPoint
    /// Size of one frame in points.
    public var size: CGSize
    public var representations: [Data]

    public var id: String { identifier }
    public var name: String { CursorNames.name(for: identifier) }
    public var isAnimated: Bool { frameCount > 1 }

    public init(identifier: String, frameCount: Int = 1, frameDuration: Double = 1,
                hotSpot: CGPoint = .zero, size: CGSize, representations: [Data]) {
        self.identifier = identifier
        self.frameCount = frameCount
        self.frameDuration = frameDuration
        self.hotSpot = hotSpot
        self.size = size
        self.representations = representations
    }

    init(identifier: String, propertyList dict: [String: Any]) throws {
        func number(_ key: String) -> Double? { (dict[key] as? NSNumber)?.doubleValue }
        guard let width = number(Key.pointsWide), let height = number(Key.pointsHigh),
              width > 0, height > 0,
              let reps = dict[Key.representations] as? [Data] else {
            throw CapeError.invalidCursor(identifier)
        }
        self.init(identifier: identifier,
                  frameCount: max(1, Int(number(Key.frameCount) ?? 1)),
                  frameDuration: number(Key.frameDuration) ?? 1,
                  hotSpot: CGPoint(x: number(Key.hotSpotX) ?? 0, y: number(Key.hotSpotY) ?? 0),
                  size: CGSize(width: width, height: height),
                  representations: reps)
    }

    var propertyList: [String: Any] {
        [
            Key.frameCount: frameCount,
            Key.frameDuration: frameDuration,
            Key.hotSpotX: hotSpot.x,
            Key.hotSpotY: hotSpot.y,
            Key.pointsWide: size.width,
            Key.pointsHigh: size.height,
            Key.representations: representations,
        ]
    }

    /// The frames, top to bottom, from the smallest representation at least `scale` times the
    /// point size (or the sharpest one there is). Empty if no image decodes.
    public func frames(scale: Int = .max) -> [CGImage] {
        guard let sheet = representation(atLeast: scale) else { return [] }
        let frameHeight = sheet.height / frameCount
        guard frameHeight > 0 else { return [] }
        return (0..<frameCount).compactMap { index in
            sheet.cropping(to: CGRect(x: 0, y: index * frameHeight, width: sheet.width, height: frameHeight))
        }
    }

    /// Pixel densities present, e.g. [1, 2, 5, 10].
    public var scales: [Int] {
        representations.compactMap { data in
            guard let rep = NSBitmapImageRep(data: data), size.width > 0 else { return nil }
            return Int((Double(rep.pixelsWide) / size.width).rounded())
        }.sorted()
    }

    private func representation(atLeast scale: Int) -> CGImage? {
        let images = representations
            .compactMap { NSBitmapImageRep(data: $0)?.cgImage }
            .sorted { $0.width < $1.width }
        let minimumWidth = Double(scale) * size.width
        return images.first { Double($0.width) >= minimumWidth } ?? images.last
    }

    /// Main pointers first (in the order macOS users meet them), the rest alphabetically.
    static func displayOrder(_ a: CapeCursor, _ b: CapeCursor) -> Bool {
        let ra = CursorNames.rank(of: a.identifier), rb = CursorNames.rank(of: b.identifier)
        if ra != rb { return ra < rb }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    enum Key {
        static let frameCount = "FrameCount"
        static let frameDuration = "FrameDuration"
        static let hotSpotX = "HotSpotX"
        static let hotSpotY = "HotSpotY"
        static let pointsWide = "PointsWide"
        static let pointsHigh = "PointsHigh"
        static let representations = "Representations"
    }
}
