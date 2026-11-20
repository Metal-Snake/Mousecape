import Foundation
import Observation
import CapeKit

/// One opening of the editor: the cape it started from, the draft being edited, what the
/// sheet shows, and the steps for Undo and Redo. Nothing touches the library until Save.
@MainActor @Observable
final class EditorSession: Identifiable {
    /// What the editor shows on the right.
    enum Item: Hashable {
        case info
        case cursor(String)
    }

    let id = UUID()
    /// The cape as the editor opened it.
    let original: Cape
    /// The identifier it is saved under in the library; nil for a new cape.
    let originalIdentifier: String?
    private(set) var draft: Cape
    var selection: Item?
    private var history = EditHistory<Cape, CapeEditPart>()

    /// Opens at `cursor` when given (e.g. from a problem), else at the details.
    init(cape: Cape, originalIdentifier: String?, cursor: String? = nil) {
        original = cape
        self.originalIdentifier = originalIdentifier
        draft = cape
        selection = cursor.map(Item.cursor) ?? .info
    }

    /// A new cape counts as changed: saving it adds it to the library.
    var hasChanges: Bool { draft != original || originalIdentifier == nil }

    /// Every edit goes through here, so that it can be undone.
    func change(to newDraft: Cape, at time: Date = .now) {
        guard let part = newDraft.editedPart(from: draft) else { return }
        history.record(draft, part: part, coalescible: part.isCoalescible, at: time)
        draft = newDraft
    }

    func change(_ edit: (inout Cape) -> Void) {
        var newDraft = draft
        edit(&newDraft)
        change(to: newDraft)
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    var undoTitle: String? { history.undoSteps.last?.part.title }
    var redoTitle: String? { history.redoSteps.last?.part.title }

    func undo() {
        guard let step = history.undo(current: draft) else { return }
        draft = step.value
        show(step.part)
    }

    func redo() {
        guard let step = history.redo(current: draft) else { return }
        draft = step.value
        show(step.part)
    }

    /// Shows what Undo or Redo changed, so the change can be seen: the cursor, or the
    /// details. A removed cursor can't be shown; the details are shown instead.
    private func show(_ part: CapeEditPart) {
        if let identifier = part.cursorIdentifier, draft.cursors.contains(where: { $0.identifier == identifier }) {
            selection = .cursor(identifier)
        } else if case .detail = part {
            selection = .info
        } else if case .cursor(let identifier) = selection,
                  !draft.cursors.contains(where: { $0.identifier == identifier }) {
            selection = .info
        }
    }
}
