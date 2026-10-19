import Foundation
import Testing
@testable import CapeKit

@Test(arguments: ["../../Evil", "../capes", "a/b", ".hidden", "", "a:b", "back\\slash", "line\nbreak",
                  String(repeating: "x", count: 201)])
func refusesUnsafeIdentifiers(identifier: String) {
    #expect(!Cape.isValidIdentifier(identifier))
    let plist: [String: Any] = ["MinimumVersion": 2.0, "Identifier": identifier, "Cursors": [String: Any]()]
    #expect(throws: CapeError.self) { try Cape(propertyList: plist) }
}

@Test(arguments: ["local.ArakiCC.Kiriko", "com.maxrudberg.svanslosbluehazard", "local.xcursor.bibatamodernclassic",
                  "test.theme.copy.1760000000", "With Spaces", "ümlaut.ß", "a..b"])
func acceptsOrdinaryIdentifiers(identifier: String) {
    #expect(Cape.isValidIdentifier(identifier))
}

@Test func refusesUnsafeCursorKeys() {
    let plist: [String: Any] = ["MinimumVersion": 2.0, "Identifier": "test",
                                "Cursors": ["../x": ["PointsWide": 16.0, "PointsHigh": 16.0, "Representations": [Data]()]]]
    #expect(throws: CapeError.invalidCursor("../x")) { try Cape(propertyList: plist) }
}
