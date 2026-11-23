import AppKit
import QuartzCore
import SwiftUI

/// Frames shown in turn, animated by Core Animation rather than by SwiftUI.
///
/// A `TimelineView` makes SwiftUI evaluate and lay out the view again for every frame, in
/// the app's process, for every animated cursor on screen, and it kept doing that while the
/// window was hidden: a cape with a few animated cursors cost about 5 % CPU all the time.
/// Here the frames go to a layer as one repeating keyframe animation, which the render
/// server plays on its own (and not at all while the window can't be seen).
struct AnimatedFrames: NSViewRepresentable {
    let frames: [CGImage]
    /// How long each frame shows, when they all show equally long.
    var frameDuration: Double
    /// Each frame's own duration, when they differ (`FrameDurations`); used when it has one
    /// entry per frame.
    var durations: [Double]? = nil

    func makeNSView(context: Context) -> FrameLayerView {
        FrameLayerView()
    }

    func updateNSView(_ view: FrameLayerView, context: Context) {
        view.show(frames, durations: frameDurations)
    }

    /// One duration per frame, never zero (a zero-length animation would not run).
    private var frameDurations: [Double] {
        if let durations, durations.count == frames.count, durations.reduce(0, +) > 0 {
            return durations.map { max($0, 0.01) }
        }
        return Array(repeating: max(frameDuration, 0.01), count: frames.count)
    }
}

/// A layer-hosting view that ignores the mouse, so clicks, double clicks and context menus
/// reach the SwiftUI views around it.
final class FrameLayerView: NSView {
    private let frameLayer = CALayer()
    private var shownFrames: [CGImage] = []
    private var shownDurations: [Double] = []
    private static let animationKey = "frames"

    init() {
        super.init(frame: .zero)
        frameLayer.contentsGravity = .resizeAspect
        frameLayer.magnificationFilter = .linear
        frameLayer.minificationFilter = .trilinear
        // Setting the layer before `wantsLayer` makes this a layer-hosting view: AppKit
        // leaves the layer's contents alone.
        layer = frameLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ frames: [CGImage], durations: [Double]) {
        // SwiftUI calls this on every update of the view around it; restarting the animation
        // each time would make it stutter.
        guard !frames.elementsEqual(shownFrames, by: ===) || durations != shownDurations else { return }
        shownFrames = frames
        shownDurations = durations

        CATransaction.begin()
        CATransaction.setDisableActions(true)       // no cross-fade to the new contents
        frameLayer.removeAnimation(forKey: Self.animationKey)
        frameLayer.contents = frames.first
        CATransaction.commit()
        guard frames.count > 1 else { return }

        let total = durations.reduce(0, +)
        // Discrete keyframes: frame i shows from keyTimes[i] to keyTimes[i + 1].
        var start = 0.0
        var keyTimes: [NSNumber] = []
        for duration in durations {
            keyTimes.append(NSNumber(value: start / total))
            start += duration
        }
        keyTimes.append(1)

        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.keyTimes = keyTimes
        animation.calculationMode = .discrete
        animation.duration = total
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        // Start where the clock stands in the cycle, so that cursors with the same timing
        // stay in step, as they did when the frame came from the time of day.
        animation.timeOffset = CACurrentMediaTime().truncatingRemainder(dividingBy: total)
        frameLayer.add(animation, forKey: Self.animationKey)
    }
}
