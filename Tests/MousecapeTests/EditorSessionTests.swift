import Foundation
import Testing
import CapeKit
@testable import Mousecape

/// Undo and Redo in the editor: the draft goes back, and the editor shows what changed.
@MainActor
struct EditorSessionTests {
    let arrow = "com.apple.coregraphics.Arrow"
    let wait = "com.apple.coregraphics.Wait"

    func session() -> EditorSession {
        var cape = Cape(identifier: "test.cape", name: "Cape", author: "Me")
        cape.addCursor(identifier: arrow)
        cape.addCursor(identifier: wait)
        return EditorSession(cape: cape, originalIdentifier: cape.identifier)
    }

    @Test func undoesTypingAsOneStep() {
        let session = session()
        let start = Date.now
        for (offset, name) in ["C", "Co", "Cool"].enumerated() {
            var draft = session.draft
            draft.name = name
            session.change(to: draft, at: start + Double(offset) * 0.2)
        }
        #expect(session.undoTitle == "Name")
        session.undo()
        #expect(session.draft.name == "Cape")
        #expect(!session.hasChanges)
        session.redo()
        #expect(session.draft.name == "Cool")
    }

    @Test func showsTheCursorAnUndoChanges() {
        let session = session()
        session.change { $0.cursors[1].hotSpot = CGPoint(x: 5, y: 5) }
        session.selection = .info
        session.undo()
        #expect(session.selection == .cursor(wait))
        #expect(session.draft.cursors[1].hotSpot == .zero)
    }

    /// Undoing the removal of a cursor brings it back and shows it; redoing the removal
    /// leaves the details on screen.
    @Test func bringsBackARemovedCursor() {
        let session = session()
        session.selection = .cursor(wait)
        session.change { $0.removeCursor(identifier: wait) }
        session.selection = .cursor(arrow)
        session.undo()
        #expect(session.draft.cursors.map(\.identifier) == [arrow, wait])
        #expect(session.selection == .cursor(wait))
        session.redo()
        #expect(session.draft.cursors.map(\.identifier) == [arrow])
        #expect(session.selection == .info)
    }

    @Test func anEditThatChangesNothingIsNoStep() {
        let session = session()
        session.change { $0.name = "Cape" }
        #expect(!session.canUndo)
    }
}
