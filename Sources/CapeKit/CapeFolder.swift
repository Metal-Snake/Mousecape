import Foundation
import CoreGraphics

/// Builds a cape from a folder that holds one subfolder per cursor, named by the cursor's
/// identifier (`com.apple.coregraphics.Arrow`), with its images: one sprite sheet per
/// scale, frames stacked vertically (`mousecloak --create`).
///
/// The images tell most of what a cursor needs. What they leave open (the hot spot, and the
/// frame count of a sheet that isn't square) comes from a `cursor.plist` in the cursor's
/// folder or from the caller, who may ask the user. The folder's contents are untrusted
/// input like any theme: identifiers are checked, and image sizes are read from the header
/// before anything is decoded.
public enum CapeFolder {
    /// The optional settings file in a cursor's folder. Its keys are those of a cursor in a
    /// cape: `HotSpotX`, `HotSpotY`, `PointsWide`, `PointsHigh`, `FrameCount`,
    /// `FrameDuration`.
    public static let settingsFileName = "cursor.plist"
    /// The frame duration used when nothing gives one, in seconds.
    public static let defaultFrameDuration = 0.1

    /// Values for one cursor; nil where nothing set them.
    public struct Settings: Equatable, Sendable {
        public var hotSpot: CGPoint?
        public var size: CGSize?
        public var frameCount: Int?
        public var frameDuration: Double?

        public init(hotSpot: CGPoint? = nil, size: CGSize? = nil, frameCount: Int? = nil, frameDuration: Double? = nil) {
            self.hotSpot = hotSpot
            self.size = size
            self.frameCount = frameCount
            self.frameDuration = frameDuration
        }

        /// Read from a `cursor.plist`. Values that are missing, of the wrong type or out of
        /// range stay nil; a hot spot or size needs both of its numbers.
        public init(propertyList: [String: Any]) {
            func number(_ key: String) -> Double? {
                guard let value = propertyList[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
                let double = value.doubleValue
                return double.isFinite ? double : nil
            }
            if let x = number("HotSpotX"), let y = number("HotSpotY"), x >= 0, y >= 0 {
                hotSpot = CGPoint(x: x, y: y)
            }
            if let width = number("PointsWide"), let height = number("PointsHigh"), width > 0, height > 0 {
                size = CGSize(width: width, height: height)
            }
            if let frames = number("FrameCount"), frames >= 1, frames == frames.rounded(), frames <= 10_000 {
                frameCount = Int(frames)
            }
            if let duration = number("FrameDuration"), duration > 0 {
                frameDuration = duration
            }
        }

        /// These settings, with `other` filling in what is still nil.
        public func filled(from other: Settings) -> Settings {
            Settings(hotSpot: hotSpot ?? other.hotSpot, size: size ?? other.size,
                     frameCount: frameCount ?? other.frameCount, frameDuration: frameDuration ?? other.frameDuration)
        }
    }

    /// A cursor folder as read from disk: its images, what they suggest, and its settings
    /// file. `cursor(with:)` turns it into a cursor.
    public struct CursorDraft: Sendable {
        public let identifier: String
        /// One image per scale, smallest first, as PNG.
        public let representations: [Data]
        /// The values from the folder's `cursor.plist`; all nil without one.
        public let fileSettings: Settings
        /// Width and height of the smallest image, which is taken as the 1x sheet.
        public let smallestPixelSize: CGSize

        /// The frame count the smallest sheet suggests: square frames stacked when its
        /// height is a multiple of its width, one frame otherwise.
        public var guessedFrameCount: Int {
            let width = Int(smallestPixelSize.width), height = Int(smallestPixelSize.height)
            guard width > 0, height > width, height % width == 0 else { return 1 }
            return height / width
        }

        /// A square sheet is one frame for certain. Any other shape may be one tall frame
        /// or several frames, which only the user knows.
        public var frameCountIsCertain: Bool {
            smallestPixelSize.width == smallestPixelSize.height
        }

        /// The cursor these images make, with `settings` (those the user gave, then the
        /// folder's, then the defaults) for what the images can't tell.
        public func cursor(with settings: Settings) -> CapeCursor {
            let frames = max(1, settings.frameCount ?? guessedFrameCount)
            let size = settings.size ?? CGSize(width: smallestPixelSize.width,
                                               height: (smallestPixelSize.height / Double(frames)).rounded())
            return CapeCursor(identifier: identifier, frameCount: frames,
                              frameDuration: settings.frameDuration ?? CapeFolder.defaultFrameDuration,
                              hotSpot: settings.hotSpot ?? .zero, size: size, representations: representations)
        }
    }

    public enum FolderError: LocalizedError, Equatable {
        case notAFolder(String)
        case noCursorFolders(String)

        public var errorDescription: String? {
            switch self {
            case .notAFolder(let path):
                String(localized: "\(path) is not a folder.")
            case .noCursorFolders(let path):
                String(localized: "\(path) has no cursor folders with images (one folder per cursor, named by its identifier).")
            }
        }
    }

    /// The cursors in `folder`, sorted by identifier, and notes on what was left out and why
    /// (folders whose name isn't a valid identifier, files that aren't images or are too
    /// large, a second image of the same width).
    public static func drafts(at folder: URL) throws -> (drafts: [CursorDraft], notes: [String]) {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FolderError.notAFolder(folder.path)
        }
        var drafts: [CursorDraft] = []
        var notes: [String] = []
        let entries = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: .skipsHiddenFiles)
        for cursorFolder in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? cursorFolder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let identifier = cursorFolder.lastPathComponent
            guard Cape.isValidIdentifier(identifier) else {
                notes.append(String(localized: "Skipped the folder \(identifier): not a valid cursor identifier."))
                continue
            }
            let (draft, cursorNotes) = Self.draft(identifier: identifier, folder: cursorFolder)
            notes += cursorNotes
            if let draft { drafts.append(draft) }
        }
        guard !drafts.isEmpty else { throw FolderError.noCursorFolders(folder.path) }
        return (drafts, notes)
    }

    /// One cursor folder: its images, smallest first, and its settings file.
    private static func draft(identifier: String, folder: URL) -> (CursorDraft?, [String]) {
        var notes: [String] = []
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                   options: .skipsHiddenFiles)) ?? []
        var images: [(png: Data, size: CGSize)] = []
        var settings = Settings()
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if file.lastPathComponent == settingsFileName {
                if let data = try? Data(contentsOf: file),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                    settings = Settings(propertyList: plist)
                } else {
                    notes.append(String(localized: "\(identifier): \(settingsFileName) can't be read; ignored."))
                }
                continue
            }
            // Untrusted input: the size comes from the header, before anything is decoded.
            guard let data = try? Data(contentsOf: file), let size = CursorSheet.pixelSize(of: data) else {
                notes.append(String(localized: "\(identifier): skipped \(file.lastPathComponent), not an image."))
                continue
            }
            guard size.width >= 1, size.height >= 1, size.width * size.height <= Double(CursorSheet.maximumPixels),
                  let normalized = CapeCursor.normalizedPNG(from: data) else {
                notes.append(String(localized: "\(identifier): skipped \(file.lastPathComponent), too large or unreadable."))
                continue
            }
            guard !images.contains(where: { $0.size.width == size.width }) else {
                notes.append(String(localized: "\(identifier): skipped \(file.lastPathComponent), another image has the same width."))
                continue
            }
            images.append((normalized.png, size))
        }
        guard let smallest = images.min(by: { $0.size.width < $1.size.width }) else {
            notes.append(String(localized: "Skipped the folder \(identifier): no images."))
            return (nil, notes)
        }
        let sorted = images.sorted { $0.size.width < $1.size.width }
        return (CursorDraft(identifier: identifier, representations: sorted.map(\.png),
                            fileSettings: settings, smallestPixelSize: smallest.size), notes)
    }

    /// The identifier a cape made from a folder gets when none is given: `local.<name>`.
    public static func defaultIdentifier(forName name: String) -> String {
        "local.\(Cape.slug(name, otherwise: "cape"))"
    }
}
