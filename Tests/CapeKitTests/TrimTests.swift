import AppKit
import Testing
@testable import CapeKit

/// A sheet of `frames` frames, `points` square at `scale`, each with an opaque rectangle
/// (in points, from the top-left) and optionally a faint pixel.
private func sheet(points: Int, scale: Int, rects: [CGRect], faint: CGPoint? = nil) throws -> Data {
    let side = points * scale
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(data: nil, width: side, height: side * rects.count, bitsPerComponent: 8,
                                         bytesPerRow: 0, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    for (index, rect) in rects.enumerated() {
        // Frame `index` from the top; drawing counts from the bottom.
        let top = CGFloat((rects.count - index) * side)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: rect.minX * CGFloat(scale), y: top - rect.maxY * CGFloat(scale),
                            width: rect.width * CGFloat(scale), height: rect.height * CGFloat(scale)))
        if let faint {
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.05))
            context.fill(CGRect(x: faint.x * CGFloat(scale), y: top - (faint.y + 1) * CGFloat(scale),
                                width: CGFloat(scale), height: CGFloat(scale)))
        }
    }
    let image = try #require(context.makeImage())
    return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
}

private func cursor(points: Int = 48, rects: [CGRect], hotSpot: CGPoint, faint: CGPoint? = nil) throws -> CapeCursor {
    CapeCursor(identifier: "x", frameCount: rects.count, frameDuration: 0.1, hotSpot: hotSpot,
               size: CGSize(width: points, height: points),
               representations: [try sheet(points: points, scale: 1, rects: rects, faint: faint),
                                 try sheet(points: points, scale: 2, rects: rects, faint: faint)])
}

@Test func trimsTransparentMarginKeepingOnePoint() throws {
    // An 18 x 29 arrow at (5, 3) on a 48-point canvas, like Obsidian.
    let original = try cursor(rects: [CGRect(x: 5, y: 3, width: 18, height: 29)], hotSpot: CGPoint(x: 7, y: 5))
    let trimmed = try #require(original.trimmingTransparentMargins())
    #expect(trimmed.size == CGSize(width: 20, height: 31))
    #expect(trimmed.hotSpot == CGPoint(x: 3, y: 3))
    #expect(trimmed.scales == [1, 2])
    #expect(trimmed.problems.isEmpty)
    // The artwork is still all there: 18 x 29 opaque points.
    let frame = try #require(trimmed.frames(scale: 1).first)
    let rep = NSBitmapImageRep(cgImage: frame)
    var opaque = 0
    for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { opaque += 1 } }
    #expect(opaque == 18 * 29)
}

@Test func trimsToTheUnionOfAllFrames() throws {
    // A ball moving right: the trimmed area must hold every position.
    let original = try cursor(rects: [CGRect(x: 10, y: 10, width: 8, height: 8),
                                      CGRect(x: 20, y: 12, width: 8, height: 8)], hotSpot: CGPoint(x: 14, y: 14))
    let trimmed = try #require(original.trimmingTransparentMargins())
    #expect(trimmed.size == CGSize(width: 20, height: 12))          // x 9..<29, y 9..<21
    #expect(trimmed.hotSpot == CGPoint(x: 5, y: 5))
    #expect(trimmed.frameCount == 2)
}

@Test func keepsHotSpotAndFaintShadowsInside() throws {
    // The hot spot lies left of the artwork, a faint shadow pixel below it.
    let original = try cursor(rects: [CGRect(x: 20, y: 20, width: 4, height: 4)],
                              hotSpot: CGPoint(x: 2, y: 22), faint: CGPoint(x: 22, y: 40))
    let trimmed = try #require(original.trimmingTransparentMargins())
    #expect(trimmed.hotSpot.x == 0)
    #expect(trimmed.size == CGSize(width: 23, height: 23))          // x 2..<25, y 19..<42
    #expect(trimmed.hotSpot.y == 3)
}

@Test func leavesFullAndEmptyCursorsAlone() throws {
    let full = try cursor(points: 8, rects: [CGRect(x: 0, y: 0, width: 8, height: 8)], hotSpot: .zero)
    #expect(full.trimmingTransparentMargins() == full)
    let empty = try cursor(points: 8, rects: [.zero], hotSpot: .zero)
    #expect(empty.trimmingTransparentMargins() == empty)
}
