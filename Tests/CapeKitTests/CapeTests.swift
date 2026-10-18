import Foundation
import Testing
@testable import CapeKit

/// The sample cape that ships in Examples/.
let sampleURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Examples/com.maxrudberg.svanslosbluehazard.cape")

@Test func readsMetadata() throws {
    let cape = try Cape(contentsOf: sampleURL)
    #expect(cape.identifier == "com.maxrudberg.svanslosbluehazard")
    #expect(cape.name == "Svanslös Blue")
    #expect(cape.author == "Max Rudberg")
    #expect(cape.isHiDPI)
    #expect(cape.fileURL == sampleURL)
    #expect(cape.cursors.count == 4)
}

@Test func ordersProminentCursorsFirst() throws {
    let cape = try Cape(contentsOf: sampleURL)
    #expect(cape.cursors.map(\.name) == ["Arrow", "Wait", "Copy", "Not Allowed"])
}

@Test func splitsAnimatedSheetIntoFrames() throws {
    let cape = try Cape(contentsOf: sampleURL)
    let wait = try #require(cape.cursors.first { $0.identifier == "com.apple.coregraphics.Wait" })
    #expect(wait.frameCount == 15)
    #expect(wait.isAnimated)
    let frames = wait.frames()
    #expect(frames.count == 15)
    // Every frame keeps the cursor's aspect ratio (28 × 40 points).
    let first = try #require(frames.first)
    #expect(abs(Double(first.width) / Double(first.height) - 28.0 / 40.0) < 0.01)
}

@Test func picksRepresentationForScale() throws {
    let cape = try Cape(contentsOf: sampleURL)
    let arrow = try #require(cape.cursors.first)            // 20 points wide
    #expect(arrow.frames(scale: 2).first?.width == 40)
    #expect(arrow.frames(scale: 3).first?.width == 100)     // next one up is 5x
    #expect(arrow.frames().first?.width == 200)             // sharpest
}

@Test func reportsScales() throws {
    let cape = try Cape(contentsOf: sampleURL)
    let arrow = try #require(cape.cursors.first)
    #expect(arrow.scales == [1, 2, 5, 10])
}

@Test func roundTripsThroughPropertyList() throws {
    let cape = try Cape(contentsOf: sampleURL)
    let copy = try Cape(propertyListData: cape.propertyListData())
    #expect(copy.identifier == cape.identifier)
    #expect(copy.cursors.map(\.identifier) == cape.cursors.map(\.identifier))
    #expect(copy.cursors.map(\.representations) == cape.cursors.map(\.representations))
    #expect(copy.cursors.map(\.hotSpot) == cape.cursors.map(\.hotSpot))
}

@Test func rejectsNewerFormat() throws {
    let plist: [String: Any] = ["MinimumVersion": 3.0, "Identifier": "x", "Cursors": [String: Any]()]
    #expect(throws: CapeError.unsupportedVersion(3.0)) { try Cape(propertyList: plist) }
}

@Test func rejectsNonCape() throws {
    let data = try PropertyListSerialization.data(fromPropertyList: ["a": 1], format: .xml, options: 0)
    #expect(throws: CapeError.notACape) { try Cape(propertyListData: data) }
}
