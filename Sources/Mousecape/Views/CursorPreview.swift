import SwiftUI
import CapeKit

/// A cursor drawn at `zoom` times its real size, animated when it has several frames (with
/// each frame's own duration when the cursor has them).
struct CursorPreview: View {
    let cursor: CapeCursor
    var zoom: CGFloat = 1
    /// Draws a small red dot where the click lands.
    var showsHotSpot = false

    @Environment(\.displayScale) private var displayScale
    @State private var frames: [CGImage] = []
    /// Whether the frames have been decoded at least once. Until then a spinner stands in for
    /// the cursor, so a big cape's tiles aren't empty squares; a cursor that can't be decoded
    /// shows a sign instead.
    @State private var loaded = false

    private var displaySize: CGSize {
        CGSize(width: cursor.size.width * zoom, height: cursor.size.height * zoom)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !frames.isEmpty {
                AnimatedFrames(frames: frames, frameDuration: cursor.frameDuration, durations: cursor.frameDurations)
                    .frame(width: displaySize.width, height: displaySize.height)
            } else if !loaded {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: displaySize.width, height: displaySize.height)
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .foregroundStyle(.secondary)
                    .frame(width: displaySize.width, height: displaySize.height)
            }
            if showsHotSpot {
                Circle()
                    .fill(.red)
                    .frame(width: 5, height: 5)
                    .offset(x: cursor.hotSpot.x * zoom - 2.5, y: cursor.hotSpot.y * zoom - 2.5)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .task(id: cursor) {     // the whole cursor, so edited images and frame counts show
            frames = await FrameCache.shared.frames(for: cursor, scale: Int((displayScale * zoom).rounded(.up)))
            loaded = true
        }
        .accessibilityLabel(cursor.name)
    }
}
