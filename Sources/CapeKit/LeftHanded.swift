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

    /// `com.apple.coregraphics.Arrow` for `…ArrowS`: the variants newer macOS versions add.
    public static func baseOfVariant(_ identifier: String) -> String? {
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

    public var leftHandedLook: LeftHandedLook {
        if hasOwnLeftHandedImages { return .ownImages }
        return mirrorForLeftHanded ?? CursorNames.isPointer(identifier) ? .mirrored : .unchanged
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
            guard let sheet = NSBitmapImageRep(data: data)?.cgImage,
                  let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: sheet.width, height: sheet.height, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.translateBy(x: CGFloat(sheet.width), y: 0)
            context.scaleBy(x: -1, y: 1)
            context.draw(sheet, in: CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height))
            guard let image = context.makeImage(),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
            mirrored.append(png)
        }
        return mirrored
    }

    /// The cursor as left-handed mode shows it (own images, mirrored, or unchanged); nil if
    /// mirroring fails.
    public var leftHanded: CapeCursor? {
        var copy = self
        copy.leftHandedRepresentations = []
        switch leftHandedLook {
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
    /// How a cursor of this cape looks in left-handed mode, as the engine applies it: a
    /// variant such as IBeamS without a setting of its own takes its base's mirror setting.
    public func leftHandedLook(of cursor: CapeCursor) -> CapeCursor.LeftHandedLook {
        guard cursor.mirrorForLeftHanded == nil, !cursor.hasOwnLeftHandedImages,
              let base = CursorNames.baseOfVariant(cursor.identifier),
              let flag = cursors.first(where: { $0.identifier == base })?.mirrorForLeftHanded else {
            return cursor.leftHandedLook
        }
        return flag ? .mirrored : .unchanged
    }

    /// In left-handed mode: cursors that look like they point with a tip at the top left
    /// (their hot spot is there) but stay unmirrored while the arrow is mirrored, the way
    /// some capes draw the I-beam as an arrow. Keyed by cursor identifier.
    public var unevenMirroring: [String: CursorProblem] {
        guard let arrow = cursors.first(where: { $0.identifier == "com.apple.coregraphics.Arrow" }),
              leftHandedLook(of: arrow) != .unchanged else { return [:] }
        var problems: [String: CursorProblem] = [:]
        for cursor in cursors where leftHandedLook(of: cursor) == .unchanged && cursor.size.width > 8 {
            let x = cursor.hotSpot.x / cursor.size.width, y = cursor.hotSpot.y / cursor.size.height
            if x < 0.3 && y < 0.3 { problems[cursor.identifier] = .notMirroredLikeArrow }
        }
        return problems
    }
}
