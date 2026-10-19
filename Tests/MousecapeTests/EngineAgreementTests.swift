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

@Test(arguments: ["local.ArakiCC.Kiriko", "With Spaces", "a..b", "../../Evil", "a/b", ".hidden", "", "a:b",
                  "back\\slash", "line\nbreak", String(repeating: "x", count: 201)])
func identifierRuleMatchesEngine(identifier: String) {
    #expect(MCIsSafeIdentifier(identifier) == Cape.isValidIdentifier(identifier))
}
