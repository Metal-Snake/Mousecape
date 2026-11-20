import Foundation

/// The steps for Undo and Redo: each step is the state before an edit. Quick edits of the
/// same part (typing a name, clicking through hot spots) make one step, as in other Mac
/// apps, so Undo doesn't take back one letter at a time.
public struct EditHistory<Value: Sendable, Part: Hashable & Sendable>: Sendable {
    /// One step: the state to go back (or forward) to, and what the edit changed.
    public struct Step: Sendable {
        public let value: Value
        public let part: Part
    }

    /// Edits of the same part closer together than this make one step.
    public static var coalescingInterval: TimeInterval { 1 }
    /// Steps kept; the oldest go first.
    public static var limit: Int { 100 }

    public private(set) var undoSteps: [Step] = []
    public private(set) var redoSteps: [Step] = []
    /// The last edit, for joining the next one to it.
    private var lastEdit: (part: Part, time: Date)?

    public init() {}

    public var canUndo: Bool { !undoSteps.isEmpty }
    public var canRedo: Bool { !redoSteps.isEmpty }

    /// Records an edit: `previous` is the state before it. A `coalescible` edit joins the
    /// step before when it changed the same part shortly after; that step already holds
    /// the state before both. Any edit ends the steps Redo could go to.
    public mutating func record(_ previous: Value, part: Part, coalescible: Bool, at time: Date = .now) {
        let joinsLastStep = coalescible && !undoSteps.isEmpty && lastEdit.map {
            $0.part == part && time.timeIntervalSince($0.time) < Self.coalescingInterval
        } == true
        if !joinsLastStep {
            undoSteps.append(Step(value: previous, part: part))
            if undoSteps.count > Self.limit { undoSteps.removeFirst(undoSteps.count - Self.limit) }
        }
        redoSteps.removeAll()
        lastEdit = (part, time)
    }

    /// The state to go back to; `current` becomes the step Redo goes to.
    public mutating func undo(current: Value) -> Step? {
        guard let step = undoSteps.popLast() else { return nil }
        redoSteps.append(Step(value: current, part: step.part))
        lastEdit = nil      // the next edit is a step of its own
        return step
    }

    /// The state Undo left; `current` becomes the step Undo goes to.
    public mutating func redo(current: Value) -> Step? {
        guard let step = redoSteps.popLast() else { return nil }
        undoSteps.append(Step(value: current, part: step.part))
        lastEdit = nil
        return step
    }
}

/// What an edit of a cape changed, for joining quick edits into one Undo step, for the
/// Undo menu item's name, and for showing the part again after Undo.
public enum CapeEditPart: Hashable, Sendable {
    public enum Detail: Hashable, Sendable {
        case name, author, version, hiDPI, identifier
    }

    public enum CursorField: Hashable, Sendable {
        case hotSpot, size, frames, images, leftHanded
        /// More than one field, such as choosing frames (frames, images and size).
        case several
    }

    case detail(Detail)
    case cursor(String, CursorField)
    case addedCursor(String)
    case removedCursor(String)
    /// More than one detail or cursor at once.
    case several

    /// Edits that come in quick runs (typing, steppers, clicks in the preview) join into one
    /// step. Adding or removing a cursor is always a step of its own.
    public var isCoalescible: Bool {
        switch self {
        case .detail, .cursor: true
        case .addedCursor, .removedCursor, .several: false
        }
    }

    /// The cursor the edit was about, to show it again after Undo.
    public var cursorIdentifier: String? {
        switch self {
        case .cursor(let identifier, _), .addedCursor(let identifier), .removedCursor(let identifier): identifier
        case .detail, .several: nil
        }
    }

    /// The name in the Undo and Redo menu items: "Undo \(title)".
    public var title: String {
        switch self {
        case .detail(.name): String(localized: "Name")
        case .detail(.author): String(localized: "Author")
        case .detail(.version): String(localized: "Version")
        case .detail(.hiDPI): String(localized: "HiDPI")
        case .detail(.identifier): String(localized: "Identifier")
        case .cursor(let identifier, let field):
            Self.title(of: field, cursor: CursorNames.name(for: identifier))
        case .addedCursor(let identifier): String(localized: "Add \(CursorNames.name(for: identifier))")
        case .removedCursor(let identifier): String(localized: "Remove \(CursorNames.name(for: identifier))")
        case .several: String(localized: "Changes")
        }
    }

    private static func title(of field: CursorField, cursor name: String) -> String {
        switch field {
        case .hotSpot: String(localized: "\(name) Hot Spot")
        case .size: String(localized: "\(name) Size")
        case .frames: String(localized: "\(name) Frames")
        case .images: String(localized: "\(name) Images")
        case .leftHanded: String(localized: "\(name) Left-Handed Look")
        case .several: String(localized: "\(name) Changes")
        }
    }
}

extension Cape {
    /// What changed from `old` to this cape; nil when nothing did.
    public func editedPart(from old: Cape) -> CapeEditPart? {
        var parts: [CapeEditPart] = []
        if name != old.name { parts.append(.detail(.name)) }
        if author != old.author { parts.append(.detail(.author)) }
        if version != old.version { parts.append(.detail(.version)) }
        if isHiDPI != old.isHiDPI { parts.append(.detail(.hiDPI)) }
        if identifier != old.identifier { parts.append(.detail(.identifier)) }

        let oldCursors = Dictionary(old.cursors.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let newIdentifiers = Set(cursors.map(\.identifier))
        for cursor in cursors {
            guard let previous = oldCursors[cursor.identifier] else {
                parts.append(.addedCursor(cursor.identifier))
                continue
            }
            if let field = cursor.editedField(from: previous) { parts.append(.cursor(cursor.identifier, field)) }
        }
        for identifier in oldCursors.keys.sorted() where !newIdentifiers.contains(identifier) {
            parts.append(.removedCursor(identifier))
        }
        if parts.isEmpty && self != old { return .several }     // e.g. only the order or other keys
        return parts.count > 1 ? .several : parts.first
    }
}

extension CapeCursor {
    /// The field that changed from `old`; nil when nothing did.
    func editedField(from old: CapeCursor) -> CapeEditPart.CursorField? {
        var fields: [CapeEditPart.CursorField] = []
        if hotSpot != old.hotSpot { fields.append(.hotSpot) }
        if size != old.size { fields.append(.size) }
        if frameCount != old.frameCount || frameDuration != old.frameDuration || frameDurations != old.frameDurations {
            fields.append(.frames)
        }
        if representations != old.representations { fields.append(.images) }
        if mirrorForLeftHanded != old.mirrorForLeftHanded || leftHandedRepresentations != old.leftHandedRepresentations
            || leftHandedHotSpot != old.leftHandedHotSpot {
            fields.append(.leftHanded)
        }
        if fields.isEmpty && self != old { return .several }
        return fields.count > 1 ? .several : fields.first
    }
}
