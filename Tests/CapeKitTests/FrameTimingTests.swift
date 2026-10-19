import AppKit
import Testing
@testable import CapeKit

/// A sheet of `count` frames, each a different shade, `side` pixels square.
private func shadedSheet(count: Int, side: Int = 4) throws -> Data {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(data: nil, width: side, height: side * count, bitsPerComponent: 8,
                                         bytesPerRow: 0, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    for index in 0..<count {
        context.setFillColor(CGColor(red: CGFloat(index) / CGFloat(count), green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: (count - 1 - index) * side, width: side, height: side))
    }
    let image = try #require(context.makeImage())
    return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
}

@Test func byTimeExpandsExactlyWhenItFits() {
    // 2, 4 and 2 jiffies: four 2-jiffy slots.
    let result = FrameSelection.byTime(durations: [2.0 / 60, 4.0 / 60, 2.0 / 60])
    #expect(result.frames == [0, 1, 1, 2])
    #expect(abs(result.duration - 2.0 / 60) < 1e-9)
    // Milliseconds: 40, 80 → 40 ms slots.
    #expect(FrameSelection.byTime(durations: [0.04, 0.08]).frames == [0, 1, 1])
}

@Test func byTimeSamplesTheLoopWhenTooLong() {
    // 1 jiffy, then 40: a 24th of the loop is 1.7 jiffies. Only the first slot's middle
    // (0.85 jiffies) falls in frame 0; frame 1 fills the rest.
    let short = FrameSelection.byTime(durations: [1.0 / 60, 40.0 / 60])
    #expect(short.frames == [0] + Array(repeating: 1, count: 23))
    #expect(abs(short.duration * 24 - 41.0 / 60) < 1e-9)              // the loop keeps its length

    // 30 frames: 10 long (100 ms), then 20 short (10 ms) → the long ones take 5/6 of the
    // loop, so 20 of the 24 slots.
    let durations = Array(repeating: 0.1, count: 10) + Array(repeating: 0.01, count: 20)
    let mixed = FrameSelection.byTime(durations: durations)
    #expect(mixed.frames.count == 24)
    #expect(mixed.frames.filter { $0 < 10 }.count == 20)
    #expect(mixed.frames == mixed.frames.sorted())                    // in order, repeats allowed
}

@Test func keepsFrameDurationsThroughPropertyList() throws {
    let cursor = CapeCursor(identifier: "com.apple.coregraphics.Wait", frameCount: 3, frameDurations: [0.1, 0.2, 0.3],
                            size: CGSize(width: 4, height: 4), representations: [try shadedSheet(count: 3)])
    #expect(cursor.frameDurations == [0.1, 0.2, 0.3])
    #expect(abs(cursor.frameDuration - 0.2) < 1e-9)                    // the average, for macOS
    #expect(cursor.problems.contains(.timedByDurations(from: 3, to: 6)))   // 100/200/300 ms → 100 ms slots
    #expect(cursor.appliedFrameCount == 6)
    let copy = try CapeCursor(identifier: cursor.identifier, propertyList: cursor.propertyList)
    #expect(copy.frameDurations == [0.1, 0.2, 0.3])
}

@Test func dropsFrameDurationsWhenFramesOrTimingChange() throws {
    let base = CapeCursor(identifier: "x", frameCount: 3, frameDurations: [0.1, 0.2, 0.3],
                          size: CGSize(width: 4, height: 4), representations: [try shadedSheet(count: 3)])
    var fewer = base
    fewer.frameCount = 2
    #expect(fewer.frameDurations == nil)
    var slower = base
    slower.frameDuration = 0.5
    #expect(slower.frameDurations == nil)
    #expect(try #require(base.keepingFrames([0, 2], frameDuration: 0.3)).frameDurations == nil)
    // Equal durations aren't kept at all.
    #expect(CapeCursor(identifier: "x", frameCount: 2, frameDurations: [0.1, 0.1],
                       size: CGSize(width: 4, height: 4), representations: []).frameDurations == nil)
}

@Test func keepingFramesByTimeRepeatsFrames() throws {
    let cursor = CapeCursor(identifier: "x", frameCount: 3, frameDurations: [0.1, 0.2, 0.1],
                            size: CGSize(width: 4, height: 4), representations: [try shadedSheet(count: 3)])
    let timing = FrameSelection.byTime(durations: try #require(cursor.frameDurations))
    #expect(timing.frames == [0, 1, 1, 2])
    let result = try #require(cursor.keepingFrames(timing.frames, frameDuration: timing.duration))
    #expect(result.frameCount == 4)
    #expect(abs(result.frameDuration - 0.1) < 1e-9)
    #expect(result.frameDurations == nil)
    #expect(result.problems.isEmpty)
    // reducingFrames (the editor's "Reduce to") does the same as the engine.
    #expect(try #require(cursor.reducingFrames()).frameCount == 4)
}
