import SwiftUI
import CapeKit

/// A cursor drawn at `zoom` times its real size, animated when it has several frames.
struct CursorPreview: View {
    let cursor: CapeCursor
    var zoom: CGFloat = 1
    /// Draws a small red dot where the click lands.
    var showsHotSpot = false

    @Environment(\.displayScale) private var displayScale
    @State private var frames: [CGImage] = []

    private var displaySize: CGSize {
        CGSize(width: cursor.size.width * zoom, height: cursor.size.height * zoom)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: max(cursor.frameDuration, 0.01), paused: frames.count < 2)) { context in
            ZStack(alignment: .topLeading) {
                if let frame = frame(at: context.date) {
                    Image(decorative: frame, scale: 1)
                        .resizable()
                        .interpolation(.high)
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
        }
        .task(id: cursor) {     // the whole cursor, so edited images and frame counts show
            frames = cursor.frames(scale: Int((displayScale * zoom).rounded(.up)))
        }
        .accessibilityLabel(cursor.name)
    }

    private func frame(at date: Date) -> CGImage? {
        guard !frames.isEmpty else { return nil }
        let step = max(cursor.frameDuration, 0.01)
        let index = Int(date.timeIntervalSinceReferenceDate / step) % frames.count
        return frames[index]
    }
}
