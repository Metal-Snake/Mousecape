import AppKit
import CoreGraphics

extension CursorNames {
    /// The cursors left-handed mode mirrors unless a cape says otherwise: everything that
    /// points with its tip. The same list as `MCPointerCursorIdentifiers` in the engine.
    public static let pointers: Set<String> = [
        "com.apple.coregraphics.Arrow", "com.apple.coregraphics.Alias", "com.apple.coregraphics.Move",
        "com.apple.coregraphics.Wait",
        "com.apple.cursor.2", "com.apple.cursor.3", "com.apple.cursor.4", "com.apple.cursor.5",
        "com.apple.cursor.11", "com.apple.cursor.12", "com.apple.cursor.13", "com.apple.cursor.14",
        "com.apple.cursor.15", "com.apple.cursor.16", "com.apple.cursor.24", "com.apple.cursor.25",
        "com.apple.cursor.42", "com.apple.cursor.43",
    ]

    /// Whether left-handed mode mirrors `identifier` by default. A variant such as ArrowS
    /// counts when its base does.
    public static func isPointer(_ identifier: String) -> Bool {
        pointers.contains(identifier) || baseOfVariant(identifier).map(pointers.contains) == true
    }

    /// Core cursors 0 and 1: the arrow and the I-beam by number. A cape without entries of
    /// its own gives them its Arrow and IBeam when applied (`MCBaseCursorForCoreAlias`).
    public static let coreAliases = [
        "com.apple.cursor.0": "com.apple.coregraphics.Arrow",
        "com.apple.cursor.1": "com.apple.coregraphics.IBeam",
    ]

    /// The cursor `identifier` stands in for: `com.apple.coregraphics.Arrow` for `…ArrowS`
    /// (the variants newer macOS versions add) and for core cursor 0.
    public static func baseOfVariant(_ identifier: String) -> String? {
        if let base = coreAliases[identifier] { return base }
        guard identifier.hasPrefix("com.apple.coregraphics."), identifier.hasSuffix("S") else { return nil }
        let base = String(identifier.dropLast())
        return all[base] != nil ? base : nil
    }
}

extension CapeCursor {
    /// How the cursor looks in left-handed mode.
    public enum LeftHandedLook: Equatable, Sendable {
        case mirrored
        case unchanged
        case ownImages
    }

    public var hasOwnLeftHandedImages: Bool { !leftHandedRepresentations.isEmpty }

    /// How the cursor looks in left-handed mode in a cape drawn for the right hand.
    public var leftHandedLook: LeftHandedLook { leftHandedLook(inLeftHandedCape: false) }

    /// How the cursor looks in left-handed mode; in a cape drawn for the left hand
    /// (`Cape.isDrawnLeftHanded`) nothing is mirrored unless the cursor asks for it.
    public func leftHandedLook(inLeftHandedCape: Bool) -> LeftHandedLook {
        if hasOwnLeftHandedImages { return .ownImages }
        return mirrorForLeftHanded ?? mirroredAutomatically(inLeftHandedCape: inLeftHandedCape) ? .mirrored : .unchanged
    }

    /// What "Automatic" does: mirror the pointers, unless the cape is drawn for the left
    /// hand already.
    public func mirroredAutomatically(inLeftHandedCape: Bool) -> Bool {
        !inLeftHandedCape && CursorNames.isPointer(identifier)
    }

    /// Whether the hot spot is where a left-handed arrow has its tip: the right part of the
    /// upper half. A right-handed arrow has it in the left third, an arrow pointing straight
    /// up in the middle. The same rule as `MCHotSpotIsLeftHanded` in the engine.
    public var pointsLikeLeftHandedArrow: Bool {
        size.width > 0 && size.height > 0 && hotSpot.x > size.width * 0.6 && hotSpot.y < size.height * 0.5
    }

    /// The hot spot of the mirrored cursor, as the engine computes it.
    public var mirroredHotSpot: CGPoint {
        CGPoint(x: size.width - hotSpot.x - 1, y: hotSpot.y)
    }

    /// The representations flipped horizontally (every frame mirrored in place); nil if an
    /// image can't be read.
    public func mirroredRepresentations() -> [Data]? {
        var mirrored: [Data] = []
        for data in representations {
            // The whole sheet at once: flipping it horizontally flips every frame in place.
            guard let sheet = CursorSheet.decode(data),
                  let context = CursorSheet.context(width: sheet.width, height: sheet.height) else { return nil }
            context.translateBy(x: CGFloat(sheet.width), y: 0)
            context.scaleBy(x: -1, y: 1)
            context.draw(sheet, in: CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height))
            guard let png = context.makeImage().flatMap(CursorSheet.png) else { return nil }
            mirrored.append(png)
        }
        return mirrored
    }

    /// The cursor as left-handed mode shows it (own images, mirrored, or unchanged); nil if
    /// mirroring fails.
    public var leftHanded: CapeCursor? { leftHanded(inLeftHandedCape: false) }

    public func leftHanded(inLeftHandedCape: Bool) -> CapeCursor? {
        var copy = self
        copy.leftHandedRepresentations = []
        switch leftHandedLook(inLeftHandedCape: inLeftHandedCape) {
        case .unchanged:
            return copy
        case .ownImages:
            copy.representations = leftHandedRepresentations
            copy.hotSpot = leftHandedHotSpot ?? mirroredHotSpot
            return copy
        case .mirrored:
            guard let mirrored = mirroredRepresentations() else { return nil }
            copy.representations = mirrored
            copy.hotSpot = mirroredHotSpot
            return copy
        }
    }

    /// The left-handed image whose width matches `scale` times the point width.
    public func leftHandedRepresentation(for scale: Int) -> Data? {
        leftHandedRepresentations.first { Self.scale(of: $0, pointWidth: size.width) == scale }
    }

    /// Replaces (or with nil removes) the left-handed image at `scale`.
    public mutating func setLeftHandedRepresentation(_ data: Data?, for scale: Int) {
        leftHandedRepresentations.removeAll { Self.scale(of: $0, pointWidth: size.width) == scale }
        if let data { leftHandedRepresentations.append(data) }
        leftHandedRepresentations.sort { Self.pixelWidth(of: $0) < Self.pixelWidth(of: $1) }
    }

    /// Starts own left-handed images from the mirrored ones (and the mirrored hot spot), to
    /// replace where mirroring looks wrong. Returns false if an image can't be read.
    @discardableResult
    public mutating func useMirroredImagesAsLeftHanded() -> Bool {
        guard let mirrored = mirroredRepresentations() else { return false }
        leftHandedRepresentations = mirrored
        leftHandedHotSpot = mirroredHotSpot
        return true
    }
}

extension Cape {
    /// Drawn for the left hand already: the arrow points to the top right. Left-handed mode
    /// mirrors nothing of such a cape unless a cursor asks for it, since mirroring would
    /// make it right-handed again. The same rule as `MCCapeIsDrawnLeftHanded`.
    public var isDrawnLeftHanded: Bool {
        cursors.first { $0.identifier == "com.apple.coregraphics.Arrow" }?.pointsLikeLeftHandedArrow ?? false
    }

    /// How a cursor of this cape looks in left-handed mode, as the engine applies it: a
    /// variant such as IBeamS (or core cursor 1) without a setting of its own takes its
    /// base's mirror setting, and a cape drawn for the left hand isn't mirrored.
    public func leftHandedLook(of cursor: CapeCursor) -> CapeCursor.LeftHandedLook {
        guard cursor.mirrorForLeftHanded == nil, !cursor.hasOwnLeftHandedImages,
              let base = CursorNames.baseOfVariant(cursor.identifier),
              let flag = cursors.first(where: { $0.identifier == base })?.mirrorForLeftHanded else {
            return cursor.leftHandedLook(inLeftHandedCape: isDrawnLeftHanded)
        }
        return flag ? .mirrored : .unchanged
    }

    /// In left-handed mode: cursors that look like they point with a tip at the top left
    /// (their hot spot is there) but stay unmirrored while the arrow is mirrored, the way
    /// some capes draw the I-beam as an arrow. Resize cursors are left out: theirs is a
    /// direction, which mirroring would turn. Keyed by cursor identifier.
    public var unevenMirroring: [String: CursorProblem] {
        guard let arrow = cursors.first(where: { $0.identifier == "com.apple.coregraphics.Arrow" }),
              leftHandedLook(of: arrow) != .unchanged else { return [:] }
        var problems: [String: CursorProblem] = [:]
        for cursor in cursors where leftHandedLook(of: cursor) == .unchanged && cursor.size.width > 8
            && !CursorNames.isResize(cursor.identifier) {
            let x = cursor.hotSpot.x / cursor.size.width, y = cursor.hotSpot.y / cursor.size.height
            if x < 0.3 && y < 0.3 { problems[cursor.identifier] = .notMirroredLikeArrow }
        }
        return problems
    }
}
