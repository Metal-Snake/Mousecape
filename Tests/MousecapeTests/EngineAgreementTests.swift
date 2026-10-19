import Foundation
import Testing
import CapeKit
import MousecloakCore

/// CapeKit predicts what the engine does; these keep the two in step.
@Test func pointerListMatchesEngine() {
    let engine = Set((MCPointerCursorIdentifiers() as? [String]) ?? [])
    #expect(!engine.isEmpty)
    #expect(CursorNames.pointers == engine)
}
