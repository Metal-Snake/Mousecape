import Foundation

/// What tells the versions of one theme apart, when a theme offers several (a Linux and a
/// Windows file, or one archive with a Regular, a Large and an Extra-Large version): how
/// many cursors each has, how large and how sharp they are, and which are animated.
///
/// Read from the image headers only, so it is cheap even for big capes.
public struct CapeSummary: Equatable, Sendable {
    public var cursorCount: Int
    /// The arrow's size in points, or nil when the cape has no arrow.
    public var arrowSize: CGSize?
    /// The highest pixel density of the arrow (or the first cursor): 1 means soft on a
    /// Retina display, 2 and more sharp.
    public var sharpestScale: Int
    public var animatedCount: Int

    /// The arrow's height on macOS, for comparing sizes: the system arrow is 24 points
    /// high in its cape, the size most themes call "regular".
    public static let regularArrowHeight: CGFloat = 24

    public init(cursorCount: Int, arrowSize: CGSize?, sharpestScale: Int, animatedCount: Int) {
        self.cursorCount = cursorCount
        self.arrowSize = arrowSize
        self.sharpestScale = sharpestScale
        self.animatedCount = animatedCount
    }

    public init(_ cape: Cape) {
        let arrow = cape.cursors.first { $0.identifier == "com.apple.coregraphics.Arrow" }
        let sample = arrow ?? cape.cursors.first
        let scale = sample.map { cursor in
            cursor.representations.compactMap { data -> Int? in
                guard let pixels = CursorSheet.pixelSize(of: data), cursor.size.width > 0 else { return nil }
                return Int((pixels.width / cursor.size.width).rounded())
            }.max() ?? 1
        } ?? 1
        self.init(cursorCount: cape.cursors.count, arrowSize: arrow?.size, sharpestScale: max(scale, 1),
                  animatedCount: cape.cursors.filter(\.isAnimated).count)
    }

    /// How far the arrow is from the regular size; a cape without an arrow counts as far.
    var distanceFromRegularSize: CGFloat {
        guard let arrowSize else { return .greatestFiniteMagnitude }
        return abs(max(arrowSize.width, arrowSize.height) - Self.regularArrowHeight)
    }

    /// The version to suggest: the most cursors (fewer means more of macOS's own show
    /// through), then the sharpest, then the one closest to the regular size. Ties keep the
    /// first. Nil for an empty list.
    public static func suggested(among summaries: [CapeSummary]) -> Int? {
        summaries.indices.min { first, second in
            let a = summaries[first], b = summaries[second]
            if a.cursorCount != b.cursorCount { return a.cursorCount > b.cursorCount }
            if a.sharpestScale != b.sharpestScale { return a.sharpestScale > b.sharpestScale }
            if a.distanceFromRegularSize != b.distanceFromRegularSize {
                return a.distanceFromRegularSize < b.distanceFromRegularSize
            }
            return first < second
        }
    }

    /// The facts in which the versions differ, so that a choice can name and show them.
    public struct Differences: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let cursorCount = Differences(rawValue: 1 << 0)
        public static let size = Differences(rawValue: 1 << 1)
        public static let sharpness = Differences(rawValue: 1 << 2)
        public static let animation = Differences(rawValue: 1 << 3)
    }

    public static func differences(among summaries: [CapeSummary]) -> Differences {
        func varies<Value: Hashable>(_ value: (CapeSummary) -> Value) -> Bool {
            Set(summaries.map(value)).count > 1
        }
        var result: Differences = []
        if varies(\.cursorCount) { result.insert(.cursorCount) }
        if varies({ $0.arrowSize.map { "\($0.width)x\($0.height)" } ?? "" }) { result.insert(.size) }
        if varies({ min($0.sharpestScale, 2) }) { result.insert(.sharpness) }      // 2x and 5x both look sharp
        if varies(\.animatedCount) { result.insert(.animation) }
        return result
    }
}
