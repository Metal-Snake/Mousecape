import Foundation
import Testing
@testable import CapeKit

/// Undo and Redo steps, and what an edit of a cape changed.

private let start = Date(timeIntervalSinceReferenceDate: 0)

@Test func quickEditsOfOnePartMakeOneStep() {
    var history = EditHistory<String, String>()
    history.record("", part: "name", coalescible: true, at: start)
    history.record("M", part: "name", coalescible: true, at: start + 0.3)
    history.record("My", part: "name", coalescible: true, at: start + 0.6)
    #expect(history.undoSteps.map(\.value) == [""])
    // A pause, another part, or an edit that never joins starts a new step.
    history.record("My C", part: "name", coalescible: true, at: start + 5)
    history.record("x", part: "author", coalescible: true, at: start + 5.1)
    history.record("y", part: "author", coalescible: false, at: start + 5.2)
    #expect(history.undoSteps.map(\.value) == ["", "My C", "x", "y"])
}

@Test func undoAndRedoSwapStates() {
    var history = EditHistory<String, String>()
    history.record("a", part: "p", coalescible: true, at: start)
    let undoStep = history.undo(current: "b")
    #expect(undoStep?.value == "a")
    #expect(history.redoSteps.map(\.value) == ["b"])
    let redoStep = history.redo(current: "a")
    #expect(redoStep?.value == "b")
    #expect(history.undoSteps.map(\.value) == ["a"])
    let again = history.undo(current: "b"), beyond = history.undo(current: "a")
    #expect(again != nil && beyond == nil)
}

/// After Undo, an edit is a step of its own and ends Redo.
@Test func anEditAfterUndoClearsRedo() throws {
    var history = EditHistory<String, String>()
    history.record("a", part: "p", coalescible: true, at: start)
    _ = history.undo(current: "b")
    history.record("a", part: "p", coalescible: true, at: start + 0.1)
    #expect(!history.canRedo)
    #expect(history.undoSteps.count == 1)
}

@Test func keepsAtMostTheLimit() {
    var history = EditHistory<Int, Int>()
    for number in 0..<(EditHistory<Int, Int>.limit + 10) {
        history.record(number, part: number, coalescible: false, at: start)
    }
    #expect(history.undoSteps.count == EditHistory<Int, Int>.limit)
    #expect(history.undoSteps.first?.value == 10)
}

private let arrow = "com.apple.coregraphics.Arrow"
private let wait = "com.apple.coregraphics.Wait"

private func cape() -> Cape {
    var cape = Cape(identifier: "test.cape", name: "Cape", author: "Me")
    cape.addCursor(identifier: arrow)
    cape.addCursor(identifier: wait)
    return cape
}

@Test func namesWhatAnEditChanged() {
    let old = cape()
    #expect(old.editedPart(from: old) == nil)

    var renamed = old
    renamed.name = "New"
    #expect(renamed.editedPart(from: old) == .detail(.name))

    var moved = old
    moved.cursors[0].hotSpot = CGPoint(x: 3, y: 3)
    #expect(moved.editedPart(from: old) == .cursor(arrow, .hotSpot))

    var resized = moved
    resized.cursors[0].size = CGSize(width: 16, height: 16)
    #expect(resized.editedPart(from: old) == .cursor(arrow, .several))

    var removed = old
    removed.removeCursor(identifier: wait)
    #expect(removed.editedPart(from: old) == .removedCursor(wait))
    #expect(old.editedPart(from: removed) == .addedCursor(wait))

    var both = renamed
    both.removeCursor(identifier: wait)
    #expect(both.editedPart(from: old) == .several)
}

@Test func onlyFieldEditsJoin() {
    #expect(CapeEditPart.detail(.name).isCoalescible)
    #expect(CapeEditPart.cursor(arrow, .hotSpot).isCoalescible)
    #expect(!CapeEditPart.addedCursor(arrow).isCoalescible)
    #expect(!CapeEditPart.several.isCoalescible)
    #expect(CapeEditPart.removedCursor(arrow).cursorIdentifier == arrow)
}
