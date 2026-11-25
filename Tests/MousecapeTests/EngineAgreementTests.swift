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

/// Every named cursor, variants and core cursors 0 and 1 included: the engine and CapeKit
/// agree on which ones left-handed mode mirrors.
@Test(arguments: CursorNames.all.keys.sorted())
func pointerRuleMatchesEngine(identifier: String) {
    #expect(MCCursorIsPointer(identifier) == CursorNames.isPointer(identifier))
}

/// Hot spots around the edges of the rule: left third, middle, right part, lower half.
@Test(arguments: [(1.0, 1.0), (8.0, 1.0), (9.6, 1.0), (9.7, 2.0), (15.0, 0.0), (15.0, 7.9), (15.0, 8.0), (15.0, 15.0)])
func leftHandedArrowRuleMatchesEngine(x: Double, y: Double) {
    let arrow = CapeCursor(identifier: "com.apple.coregraphics.Arrow", frameCount: 1, hotSpot: CGPoint(x: x, y: y),
                           size: CGSize(width: 16, height: 16), representations: [])
    #expect(MCHotSpotIsLeftHanded(x, y, 16, 16) == arrow.pointsLikeLeftHandedArrow)
    let cape = Cape(identifier: "test", name: "T", author: "", cursors: [arrow])
    let cursors = cape.propertyList["Cursors"] as? [String: Any] ?? [:]
    #expect(MCCapeIsDrawnLeftHanded(cursors) == cape.isDrawnLeftHanded)
}

@Test func imageSizeLimitMatchesEngine() {
    #expect(Int(MCMaximumImagePixels) == CursorSheet.maximumPixels)
}

@Test func coreAliasesMatchEngine() {
    for (alias, base) in CursorNames.coreAliases {
        #expect(MCBaseCursorForCoreAlias(alias) == base)
    }
    #expect(MCBaseCursorForCoreAlias("com.apple.cursor.2") == nil)
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

@Test(arguments: timingCases, [CapeCursor.maximumFrameCount, 40, CapeCursor.longAnimationFrameLimit])
func framesByTimeMatchesEngine(durations: [Double], limit: Int) {
    var indices = [UInt](repeating: 0, count: limit)
    var duration: CGFloat = 0
    let count = Int(MCFramesByTime(durations, &indices, &duration, UInt(limit)))
    let expected = FrameSelection.byTime(durations: durations, count: limit)
    let frames: [Int] = indices[..<count].map { Int($0) }
    #expect(frames == expected.frames)
    #expect(abs(Double(duration) - expected.duration) < 1e-9)
}

@Test func longAnimationLimitsMatchEngine() {
    #expect(Int(MCMaxFrameCount) == CapeCursor.maximumFrameCount)
    #expect(Int(MCMaxLongFrameCount) == CapeCursor.longAnimationFrameLimit)
    #expect(Int(MCMaxLongAnimationPixels) == CapeCursor.longAnimationPixelLimit)
}

/// Pixels per frame from tiny cursors to huge ones, around where the pixel limit starts to
/// bite (65,536 pixels per frame allow 256 frames, 699,051 only 24).
@Test(arguments: [0, 1, 1_024, 65_536, 65_537, 133_000, 699_050, 699_051, 699_052, 10_000_000], [false, true])
func frameLimitMatchesEngine(pixelsPerFrame: Int, longAnimations: Bool) {
    #expect(Int(MCFrameLimit(UInt(pixelsPerFrame), longAnimations))
            == CapeCursor.frameLimit(pixelsPerFrame: pixelsPerFrame, longAnimations: longAnimations))
}
