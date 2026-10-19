import Foundation
import Testing
@testable import CapeKit

private func cursor(_ identifier: String, frames: Int = 1, hotSpot: CGPoint = .zero, image: UInt8 = 1) -> CapeCursor {
    CapeCursor(identifier: identifier, frameCount: frames, frameDuration: 0.1, hotSpot: hotSpot,
               size: CGSize(width: 16, height: 16), representations: [Data([image])])
}

@Test func diffOfIdenticalCapesIsEmpty() {
    let cape = Cape(identifier: "a", name: "A", author: "", cursors: [cursor("com.apple.coregraphics.Arrow")])
    #expect(CapeDiff(from: cape, to: cape).isEmpty)
}

@Test func diffListsDetailsAndCursorChanges() {
    let old = Cape(identifier: "a", name: "Old", author: "Me", cursors: [
        cursor("com.apple.coregraphics.Arrow"),
        cursor("com.apple.coregraphics.IBeam", hotSpot: CGPoint(x: 4, y: 9)),
        cursor("com.apple.cursor.13"),
    ])
    let new = Cape(identifier: "a", name: "New", author: "Me", cursors: [
        cursor("com.apple.coregraphics.Arrow"),                                      // unchanged
        cursor("com.apple.coregraphics.IBeam", frames: 2, hotSpot: CGPoint(x: 5, y: 9), image: 2),
        cursor("com.apple.coregraphics.Wait"),                                       // added
    ])
    let diff = CapeDiff(from: old, to: new)
    #expect(diff.details == [CapeDiff.DetailChange(label: "Name", old: "Old", new: "New")])
    // In display order: Pointing Hand comes before Wait.
    #expect(diff.cursors.map(\.identifier) == ["com.apple.coregraphics.IBeam", "com.apple.cursor.13",
                                               "com.apple.coregraphics.Wait"])
    #expect(diff.cursors[0].status == .changed([.hotSpot(from: CGPoint(x: 4, y: 9), to: CGPoint(x: 5, y: 9)),
                                                .frames(from: 1, to: 2), .images]))
    #expect(diff.cursors[1].status == .removed)
    #expect(diff.cursors[1].new == nil)
    #expect(diff.cursors[2].status == .added)
}
