import CoreGraphics
import Foundation
import CapeKit

/// Decoded cursor frames, shared by all previews. Decoding runs off the main thread, and
/// a cape seen once doesn't decode its sprite sheets again when you come back to it.
@MainActor
final class FrameCache {
    static let shared = FrameCache()

    private let cache: NSCache<NSString, Frames> = {
        let cache = NSCache<NSString, Frames>()
        cache.countLimit = 600
        return cache
    }()

    /// Immutable, so it can travel from the decoding task to the main actor.
    final class Frames: @unchecked Sendable {
        let images: [CGImage]
        init(_ images: [CGImage]) { self.images = images }
    }

    func frames(for cursor: CapeCursor, scale: Int) async -> [CGImage] {
        let key = Self.key(for: cursor, scale: scale)
        if let cached = cache.object(forKey: key) { return cached.images }
        let frames = await Task.detached(priority: .userInitiated) {
            Frames(cursor.frames(scale: scale))
        }.value
        cache.setObject(frames, forKey: key)
        return frames.images
    }

    /// Covers everything the frames depend on, including the full image bytes (the editor
    /// can swap in an image of the same size).
    private static func key(for cursor: CapeCursor, scale: Int) -> NSString {
        var hasher = Hasher()
        hasher.combine(cursor.frameCount)
        hasher.combine(cursor.size.width)
        hasher.combine(cursor.size.height)
        for data in cursor.representations {
            data.withUnsafeBytes { hasher.combine(bytes: $0) }
        }
        return "\(cursor.identifier)|\(scale)|\(hasher.finalize())" as NSString
    }
}
