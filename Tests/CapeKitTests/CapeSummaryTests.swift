import Foundation
import Testing
import TestSupport
@testable import CapeKit

/// A cape with an arrow of `points` at `scale`, plus `extra` more cursors (one animated).
private func cape(arrow points: Int, scale: Int, extra: Int = 0) -> Cape {
    let arrow = CapeCursor(identifier: "com.apple.coregraphics.Arrow", size: CGSize(width: points, height: points),
                           representations: [pngImage(width: points * scale, height: points * scale)])
    let others = (0..<extra).map { index in
        CapeCursor(identifier: "com.apple.cursor.\(index + 2)", frameCount: index == 0 ? 2 : 1,
                   size: CGSize(width: 16, height: 16),
                   representations: [pngImage(width: 16, height: index == 0 ? 32 : 16)])
    }
    return Cape(identifier: "local.test", name: "Test", author: "", cursors: [arrow] + others)
}

@Test func summarisesACape() {
    let summary = CapeSummary(cape(arrow: 32, scale: 2, extra: 3))
    #expect(summary == CapeSummary(cursorCount: 4, arrowSize: CGSize(width: 32, height: 32), sharpestScale: 2, animatedCount: 1))
}

@Test func suggestsMostCursorsThenSharpestThenRegularSize() {
    let regular = CapeSummary(cursorCount: 20, arrowSize: CGSize(width: 24, height: 24), sharpestScale: 1, animatedCount: 0)
    let large = CapeSummary(cursorCount: 20, arrowSize: CGSize(width: 32, height: 32), sharpestScale: 1, animatedCount: 0)
    let sharp = CapeSummary(cursorCount: 20, arrowSize: CGSize(width: 32, height: 32), sharpestScale: 2, animatedCount: 0)
    let full = CapeSummary(cursorCount: 37, arrowSize: CGSize(width: 40, height: 40), sharpestScale: 1, animatedCount: 2)
    #expect(CapeSummary.suggested(among: [large, regular]) == 1)
    #expect(CapeSummary.suggested(among: [regular, sharp]) == 1)
    #expect(CapeSummary.suggested(among: [regular, sharp, full]) == 2)
    #expect(CapeSummary.suggested(among: [regular, regular]) == 0)
    #expect(CapeSummary.suggested(among: []) == nil)
}

@Test func namesWhatDiffers() {
    let regular = CapeSummary(cape(arrow: 24, scale: 1))
    let large = CapeSummary(cape(arrow: 32, scale: 1))
    let sharp = CapeSummary(cape(arrow: 24, scale: 2, extra: 2))
    let sharper = CapeSummary(cape(arrow: 24, scale: 5, extra: 2))
    #expect(CapeSummary.differences(among: [regular, large]) == .size)
    #expect(CapeSummary.differences(among: [regular, sharp]) == [.cursorCount, .sharpness, .animation])
    #expect(CapeSummary.differences(among: [sharp, sharper]).isEmpty)        // 2x and 5x both look sharp
}
