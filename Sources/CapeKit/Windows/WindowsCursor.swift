import Foundation
import CoreGraphics

/// Turns Windows cursor files into cape cursors.
public enum WindowsCursor {
    /// Windows draws cursors at 32 × 32 pixels at the default pointer size, whatever size the
    /// file's images are; that becomes the cursor's point size here.
    public static let pointSize = 32

    /// A cape cursor for `identifier` from the contents of a `.cur`, `.ico` or `.ani` file.
    /// Images are resampled to 1x and 2x (and 5x when the source is large enough), and the
    /// transparent margin around the artwork is cut off.
    public static func capeCursor(from data: Data, identifier: String) throws -> CapeCursor {
        let frames: [WindowsIconImage]
        var frameDuration = 1.0
        var frameDurations: [Double]?
        if data.starts(with: Array("RIFF".utf8)) {
            let animation = try WindowsAni.parse(data)
            let chosen = animation.frames.map(largest)
            let timing = timeline(steps: animation.steps, rates: animation.rates)
            frames = timing.frames.map { chosen[$0] }
            frameDuration = timing.duration
            frameDurations = timing.stepDurations
        } else {
            frames = [largest(try WindowsIcon.images(from: data))]
        }
        guard let first = frames.first else { throw WindowsCursorError.notACursor }

        let source = first.image
        let pointWidth = Double(pointSize)
        let pointHeight = (pointWidth * Double(source.height) / Double(source.width)).rounded()
        let toPoints = pointWidth / Double(source.width)
        let hotSpot = CGPoint(x: (first.hotSpot.x * toPoints).rounded(), y: (first.hotSpot.y * toPoints).rounded())

        // Every frame drawn into one sheet per scale. Scales above the source's own
        // resolution would only add blur.
        let scales = CapeCursor.supportedScales.filter { $0 == 1 || pointWidth * Double($0) <= Double(source.width) }
        var representations: [Data] = []
        for scale in scales {
            let width = Int(pointWidth) * scale, height = Int(pointHeight) * scale
            guard let sheet = CursorSheet.render(frames.map(\.image), frameWidth: width, frameHeight: height) else {
                throw WindowsCursorError.unsupportedImage("resampling")
            }
            representations.append(sheet)
        }
        let cursor = CapeCursor(identifier: identifier, frameCount: frames.count, frameDuration: frameDuration,
                                frameDurations: frameDurations, hotSpot: hotSpot, size: CGSize(width: pointWidth, height: pointHeight),
                                representations: representations)
        return cursor.trimmingTransparentMargins() ?? cursor
    }

    /// The sharpest image of a frame (files often carry 32, 48, 64 … pixel versions).
    private static func largest(_ images: [WindowsIconImage]) -> WindowsIconImage {
        images.max { $0.width < $1.width } ?? images[0]
    }

    /// Frames in display order and one duration for all of them (see `CursorSheet.timeline`);
    /// Windows durations are in jiffies (1/60 s).
    static func timeline(steps: [Int], rates: [Int]) -> (frames: [Int], duration: Double, stepDurations: [Double]?) {
        CursorSheet.timeline(steps: steps, durations: rates, unit: 1.0 / 60)
    }
}
