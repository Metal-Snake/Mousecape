import Foundation
import Testing
@testable import CapeKit

private func version(_ name: String, kind: String, variant: String?) -> ThemeVersions.Version {
    let cape = Cape(identifier: "local.\(kind.lowercased()).\(Cape.slug(name, otherwise: "theme"))", name: name, author: "")
    return ThemeVersions.Version(cape: cape, variant: variant, kind: kind)
}

private let bibata = [
    version("Bibata Modern Classic", kind: "Linux", variant: "Bibata-Modern-Classic"),
    version("Bibata Modern Classic", kind: "Windows", variant: "Bibata-Modern-Classic-Windows/Bibata-Modern-Classic-Large-Windows"),
    version("Bibata Modern Classic", kind: "Windows", variant: "Bibata-Modern-Classic-Windows/Bibata-Modern-Classic-Extra-Large-Windows"),
]

@Test func labelsNameWhatTheFoldersDoNotShare() {
    #expect(ThemeVersions.labels(for: bibata) == ["Linux", "Large Windows", "Extra Large Windows"])
    // Without the Linux version, "Windows" is shared and the kinds are the same.
    #expect(ThemeVersions.labels(for: Array(bibata.dropFirst())) == ["Large", "Extra Large"])
}

@Test func labelsThatStayTheSameAreNumbered() {
    let twins = [version("Twin", kind: "Windows", variant: nil), version("Twin", kind: "Windows", variant: nil)]
    #expect(ThemeVersions.labels(for: twins) == ["Windows 1", "Windows 2"])
}

@Test func versionsGetTheirOwnNamesAndIdentifiers() {
    let capes = ThemeVersions.distinguished(bibata)
    #expect(capes.map(\.name) == ["Bibata Modern Classic (Linux)", "Bibata Modern Classic (Large Windows)",
                                  "Bibata Modern Classic (Extra Large Windows)"])
    #expect(capes.map(\.identifier) == ["local.linux.bibatamodernclassic.linux",
                                        "local.windows.bibatamodernclassic.largewindows",
                                        "local.windows.bibatamodernclassic.extralargewindows"])
    #expect(capes.allSatisfy { Cape.isValidIdentifier($0.identifier) })
}

@Test func distinctVersionsAndASingleOneStayAsTheyAre() {
    let distinct = [version("Kiriko", kind: "Windows", variant: "a"), version("Kiriko Static", kind: "Windows", variant: "b")]
    #expect(ThemeVersions.distinguished(distinct).map(\.name) == ["Kiriko", "Kiriko Static"])
    #expect(ThemeVersions.distinguished([bibata[1]]).map(\.name) == ["Bibata Modern Classic"])
}
