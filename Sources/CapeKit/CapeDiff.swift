import Foundation

/// What changed between two versions of a cape: its details, and per cursor whether it was
/// added, removed or changed, and how.
public struct CapeDiff: Equatable, Sendable {
    /// A detail of the cape itself that differs.
    public struct DetailChange: Equatable, Sendable {
        public let label: String
        public let old: String
        public let new: String
    }

    /// What can change in a cursor.
    public enum CursorChange: Hashable, Sendable, CustomStringConvertible {
        case images
        case hotSpot(from: CGPoint, to: CGPoint)
        case frames(from: Int, to: Int)
        case frameDuration(from: Double, to: Double)
        case frameTiming
        case size(from: CGSize, to: CGSize)

        public var description: String {
            switch self {
            case .images:
                String(localized: "Images changed")
            case .hotSpot(let a, let b):
                String(localized: "Hot spot \(Self.point(a)) → \(Self.point(b))")
            case .frames(let a, let b):
                String(localized: "Frames \(a) → \(b)")
            case .frameDuration(let a, let b):
                String(localized: "Frame duration \(Self.seconds(a)) → \(Self.seconds(b))")
            case .frameTiming:
                String(localized: "Frame timing changed")
            case .size(let a, let b):
                String(localized: "Size \(Self.size(a)) → \(Self.size(b)) pt")
            }
        }

        private static func number(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(0...2)))
        }
        private static func point(_ p: CGPoint) -> String { "\(number(p.x)), \(number(p.y))" }
        private static func size(_ s: CGSize) -> String { "\(number(s.width)) × \(number(s.height))" }
        private static func seconds(_ s: Double) -> String { "\(s.formatted(.number.precision(.fractionLength(0...3)))) s" }
    }

    public enum CursorStatus: Equatable, Sendable {
        case added
        case removed
        case changed([CursorChange])
    }

    public struct CursorDiff: Equatable, Sendable, Identifiable {
        public let identifier: String
        public let status: CursorStatus
        /// The cursor in the older and the newer version (nil where it doesn't exist).
        public let old: CapeCursor?
        public let new: CapeCursor?

        public var id: String { identifier }
        public var name: String { CursorNames.name(for: identifier) }
    }

    public let details: [DetailChange]
    /// Changed, added and removed cursors, in display order; unchanged ones are left out.
    public let cursors: [CursorDiff]

    public var isEmpty: Bool { details.isEmpty && cursors.isEmpty }

    /// The changes from `old` to `new`.
    public init(from old: Cape, to new: Cape) {
        var details: [DetailChange] = []
        func compare(_ label: String, _ a: String, _ b: String) {
            if a != b { details.append(DetailChange(label: label, old: a, new: b)) }
        }
        compare(String(localized: "Name"), old.name, new.name)
        compare(String(localized: "Author"), old.author, new.author)
        compare(String(localized: "Version"), old.version.formatted(), new.version.formatted())
        compare(String(localized: "Identifier"), old.identifier, new.identifier)
        compare(String(localized: "HiDPI"), old.isHiDPI ? "✓" : "–", new.isHiDPI ? "✓" : "–")
        self.details = details

        let oldCursors = Dictionary(old.cursors.map { ($0.identifier, $0) }, uniquingKeysWith: { a, _ in a })
        let newCursors = Dictionary(new.cursors.map { ($0.identifier, $0) }, uniquingKeysWith: { a, _ in a })
        var diffs: [CursorDiff] = []
        for cursor in (new.cursors + old.cursors.filter { newCursors[$0.identifier] == nil })
            .sorted(by: CapeCursor.displayOrder) {
            switch (oldCursors[cursor.identifier], newCursors[cursor.identifier]) {
            case (nil, let added?):
                diffs.append(CursorDiff(identifier: added.identifier, status: .added, old: nil, new: added))
            case (let removed?, nil):
                diffs.append(CursorDiff(identifier: removed.identifier, status: .removed, old: removed, new: nil))
            case (let a?, let b?):
                let changes = Self.changes(from: a, to: b)
                if !changes.isEmpty {
                    diffs.append(CursorDiff(identifier: a.identifier, status: .changed(changes), old: a, new: b))
                }
            default:
                break
            }
        }
        cursors = diffs
    }

    static func changes(from a: CapeCursor, to b: CapeCursor) -> [CursorChange] {
        var changes: [CursorChange] = []
        if a.size != b.size { changes.append(.size(from: a.size, to: b.size)) }
        if a.hotSpot != b.hotSpot { changes.append(.hotSpot(from: a.hotSpot, to: b.hotSpot)) }
        if a.frameCount != b.frameCount { changes.append(.frames(from: a.frameCount, to: b.frameCount)) }
        if abs(a.frameDuration - b.frameDuration) > 0.0005 {
            changes.append(.frameDuration(from: a.frameDuration, to: b.frameDuration))
        } else if a.frameDurations != b.frameDurations {
            changes.append(.frameTiming)
        }
        if a.representations != b.representations { changes.append(.images) }
        return changes
    }
}
