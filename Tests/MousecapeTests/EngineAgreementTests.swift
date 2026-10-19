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

@Test(arguments: ["local.ArakiCC.Kiriko", "With Spaces", "a..b", "a~b", "../../Evil", "a/b", ".hidden", "", "a:b",
                  "~/Documents", "~", "~Documents",
                  "back\\slash", "line\nbreak", String(repeating: "x", count: 201)])
func identifierRuleMatchesEngine(identifier: String) {
    #expect(MCIsSafeIdentifier(identifier) == Cape.isValidIdentifier(identifier))
}

/// Durations in seconds, as cape files store them.
private let timingCases: [[Double]] = [
    [2.0 / 60, 4.0 / 60, 2.0 / 60],                                     // exact, in jiffies
    [0.04, 0.08],                                                       // exact, in milliseconds
    [1.0 / 60, 40.0 / 60],                                              // sampled
    Array(repeating: 0.1, count: 10) + Array(repeating: 0.01, count: 20),
    [0.033, 0.017, 0.1, 0.25, 0.005],
]

@Test(arguments: timingCases)
func framesByTimeMatchesEngine(durations: [Double]) {
    var indices = [UInt](repeating: 0, count: CapeCursor.maximumFrameCount)
    var duration: CGFloat = 0
    let count = Int(MCFramesByTime(durations, &indices, &duration))
    let expected = FrameSelection.byTime(durations: durations)
    let frames: [Int] = indices[..<count].map { Int($0) }
    #expect(frames == expected.frames)
    #expect(abs(Double(duration) - expected.duration) < 1e-9)
}
