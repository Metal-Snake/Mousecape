import AppKit
import CoreGraphics

/// One cursor of a cape. Each representation is an image (PNG or TIFF data) holding all
/// frames stacked vertically, frame 0 at the top, at one pixel density (1x, 2x, 5x, 10x).
public struct CapeCursor: Identifiable, Equatable, Sendable {
    public var identifier: String
    public var frameCount: Int {
        didSet { if frameDurations?.count != frameCount { frameDurations = nil } }
    }
    /// Seconds per frame. With `frameDurations`, their average.
    public var frameDuration: Double {
        didSet {
            if let average = frameDurations.map(Self.average), abs(average - frameDuration) > 0.0005 {
                frameDurations = nil
            }
        }
    }
    /// Seconds for each frame, when they differ: imported animations (Windows `.ani`,
    /// Xcursor) can give each frame its own duration. macOS takes one duration for all
    /// frames, so this only feeds the time-based frame choice; the engine (and the original
    /// Mousecape) use `frameDuration`. Nil when all frames last the same; dropped when the
    /// frames or their duration change.
    public var frameDurations: [Double]?
    /// In points, from the top-left corner.
    public var hotSpot: CGPoint
    /// Size of one frame in points.
    public var size: CGSize
    public var representations: [Data]

    /// Left-handed mode: true mirrors this cursor, false leaves it as it is, nil lets the
    /// pointer list decide (`CursorNames.isPointer`). Ignored when the cursor has its own
    /// left-handed images.
    public var mirrorForLeftHanded: Bool?
    /// Images to show in left-handed mode instead of mirroring, one per scale like
    /// `representations` (same size and frames). Empty when the cursor has none.
    public var leftHandedRepresentations: [Data] = []
    /// The hot spot for `leftHandedRepresentations`; nil means the mirrored hot spot.
    public var leftHandedHotSpot: CGPoint?
    /// Keys of the file this version doesn't know; written back unchanged.
    public var otherKeys: OtherKeys = .none

    public var id: String { identifier }
    public var name: String { CursorNames.name(for: identifier) }
    public var isAnimated: Bool { frameCount > 1 }

    public init(identifier: String, frameCount: Int = 1, frameDuration: Double = 1,
                frameDurations: [Double]? = nil,
                hotSpot: CGPoint = .zero, size: CGSize, representations: [Data]) {
        self.identifier = identifier
        self.frameCount = frameCount
        self.hotSpot = hotSpot
        self.size = size
        self.representations = representations
        if let frameDurations, frameDurations.count == frameCount, frameDurations.allSatisfy({ $0 > 0 }),
           Set(frameDurations).count > 1 {
            self.frameDurations = frameDurations
            self.frameDuration = Self.average(frameDurations)
        } else {
            self.frameDuration = frameDuration
        }
    }

    static func average(_ durations: [Double]) -> Double {
        durations.reduce(0, +) / Double(max(durations.count, 1))
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
                  frameDurations: (dict[Key.frameDurations] as? [NSNumber])?.map(\.doubleValue),
                  hotSpot: CGPoint(x: number(Key.hotSpotX) ?? 0, y: number(Key.hotSpotY) ?? 0),
                  size: CGSize(width: width, height: height),
                  representations: reps)
        mirrorForLeftHanded = (dict[Key.mirrorForLeftHanded] as? NSNumber)?.boolValue
        leftHandedRepresentations = dict[Key.leftHandedRepresentations] as? [Data] ?? []
        if let x = number(Key.leftHandedHotSpotX), let y = number(Key.leftHandedHotSpotY) {
            leftHandedHotSpot = CGPoint(x: x, y: y)
        }
        otherKeys = OtherKeys(dict, known: Key.all)
    }

    var propertyList: [String: Any] {
        var dict: [String: Any] = [
            Key.frameCount: frameCount,
            Key.frameDuration: frameDuration,
            Key.hotSpotX: hotSpot.x,
            Key.hotSpotY: hotSpot.y,
            Key.pointsWide: size.width,
            Key.pointsHigh: size.height,
            Key.representations: representations,
        ]
        if let frameDurations { dict[Key.frameDurations] = frameDurations }
        if let mirrorForLeftHanded { dict[Key.mirrorForLeftHanded] = mirrorForLeftHanded }
        if !leftHandedRepresentations.isEmpty {
            dict[Key.leftHandedRepresentations] = leftHandedRepresentations
            if let leftHandedHotSpot {
                dict[Key.leftHandedHotSpotX] = leftHandedHotSpot.x
                dict[Key.leftHandedHotSpotY] = leftHandedHotSpot.y
            }
        }
        return otherKeys.merged(with: dict)
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
        static let frameDurations = "FrameDurations"
        static let hotSpotX = "HotSpotX"
        static let hotSpotY = "HotSpotY"
        static let pointsWide = "PointsWide"
        static let pointsHigh = "PointsHigh"
        static let representations = "Representations"
        static let mirrorForLeftHanded = "MirrorForLeftHanded"
        static let leftHandedRepresentations = "LeftHandedRepresentations"
        static let leftHandedHotSpotX = "LeftHandedHotSpotX"
        static let leftHandedHotSpotY = "LeftHandedHotSpotY"
        static let all: Set<String> = [frameCount, frameDuration, frameDurations, hotSpotX, hotSpotY, pointsWide,
                                       pointsHigh, representations, mirrorForLeftHanded, leftHandedRepresentations,
                                       leftHandedHotSpotX, leftHandedHotSpotY]
    }
}
