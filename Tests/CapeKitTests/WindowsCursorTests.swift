import AppKit
import Testing
import TestSupport
@testable import CapeKit

// MARK: - Writing test files

/// A 32-bit DIB from top-down RGBA pixels, with an all-clear AND mask.
private func dib32(width: Int, height: Int, rgba: [[UInt8]]) -> Data {
    var b = Bytes()
    b.u32(40); b.u32(width); b.u32(height * 2); b.u16(1); b.u16(32)
    b.u32(0); b.u32(0); b.u32(0); b.u32(0); b.u32(0); b.u32(0)
    for row in (0..<height).reversed() {                     // stored bottom-up
        for x in 0..<width {
            let p = rgba[row * width + x]
            b.u8(Int(p[2])); b.u8(Int(p[1])); b.u8(Int(p[0])); b.u8(Int(p[3]))
        }
    }
    let maskStride = ((width + 31) / 32) * 4
    b.data.append(Data(count: maskStride * height))
    return b.data
}

/// An 8-bit palette DIB (palette: black, red) whose transparency comes from the AND mask.
private func dib8(width: Int, height: Int, indices: [Int], transparent: Set<Int>) -> Data {
    var b = Bytes()
    b.u32(40); b.u32(width); b.u32(height * 2); b.u16(1); b.u16(8)
    b.u32(0); b.u32(0); b.u32(0); b.u32(0); b.u32(2); b.u32(0)
    b.u8(0); b.u8(0); b.u8(0); b.u8(0)                       // black
    b.u8(0); b.u8(0); b.u8(255); b.u8(0)                     // red (BGR order)
    let stride = ((width * 8 + 31) / 32) * 4
    for row in (0..<height).reversed() {
        var line = indices[(row * width)..<(row * width + width)].map { UInt8($0) }
        line += [UInt8](repeating: 0, count: stride - width)
        b.data.append(contentsOf: line)
    }
    let maskStride = ((width + 31) / 32) * 4
    for row in (0..<height).reversed() {
        var line = [UInt8](repeating: 0, count: maskStride)
        for x in 0..<width where transparent.contains(row * width + x) {
            line[x / 8] |= 0x80 >> UInt8(x % 8)
        }
        b.data.append(contentsOf: line)
    }
    return b.data
}

/// An `.ani` file from whole `.cur` files.
private func aniFile(frames: [Data], defaultRate: Int, rates: [Int]? = nil, sequence: [Int]? = nil,
                     stepCount: Int? = nil) -> Data {
    var body = Bytes()
    func chunk(_ id: String, _ payload: Data) {
        body.tag(id); body.u32(payload.count); body.data.append(payload)
        if payload.count % 2 == 1 { body.u8(0) }
    }
    var header = Bytes()
    header.u32(36); header.u32(frames.count); header.u32(stepCount ?? sequence?.count ?? frames.count)
    header.u32(0); header.u32(0); header.u32(0); header.u32(0)
    header.u32(defaultRate); header.u32(sequence == nil ? 1 : 3)
    chunk("anih", header.data)
    if let rates { var r = Bytes(); rates.forEach { r.u32($0) }; chunk("rate", r.data) }
    if let sequence { var s = Bytes(); sequence.forEach { s.u32($0) }; chunk("seq ", s.data) }
    var list = Bytes(); list.tag("fram")
    for frame in frames {
        list.tag("icon"); list.u32(frame.count); list.data.append(frame)
        if frame.count % 2 == 1 { list.u8(0) }
    }
    chunk("LIST", list.data)
    var riff = Bytes()
    riff.tag("RIFF"); riff.u32(body.data.count + 4); riff.tag("ACON"); riff.data.append(body.data)
    return riff.data
}

/// A solid square cursor frame in one colour, `size` pixels.
private func solidCur(size: Int, rgba: [UInt8], hotSpot: (Int, Int) = (0, 0)) -> Data {
    curFile([(dib32(width: size, height: size, rgba: Array(repeating: rgba, count: size * size)), size, hotSpot)])
}

private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> NSColor {
    NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
}

// MARK: - Reading

@Test func readsThirtyTwoBitCursorTopDown() throws {
    // Top row red, bottom row blue, 2 × 2 pixels; hot spot (1, 0).
    let red: [UInt8] = [255, 0, 0, 255], blue: [UInt8] = [0, 0, 255, 255]
    let data = curFile([(dib32(width: 2, height: 2, rgba: [red, red, blue, blue]), 2, (1, 0))])
    let image = try #require(try WindowsIcon.images(from: data).first)
    #expect(image.hotSpot == CGPoint(x: 1, y: 0))
    #expect(image.image.width == 2 && image.image.height == 2)
    #expect(pixel(image.image, 0, 0).redComponent > 0.9)            // top stays top
    #expect(pixel(image.image, 0, 1).blueComponent > 0.9)
}

@Test func usesTheMaskWithoutAlpha() throws {
    // 8-bit palette image: pixel 0 black and masked out (transparent), pixel 1 red.
    let data = curFile([(dib8(width: 2, height: 1, indices: [0, 1], transparent: [0]), 2, (0, 0))])
    let image = try #require(try WindowsIcon.images(from: data).first).image
    #expect(pixel(image, 0, 0).alphaComponent < 0.01)
    #expect(pixel(image, 1, 0).alphaComponent > 0.99)
    #expect(pixel(image, 1, 0).redComponent > 0.9)
}

@Test func drawsInvertingPixelsBlack() throws {
    // A set mask bit over a coloured pixel means "invert the screen" on Windows; macOS
    // cursors can't, so it is drawn opaque black.
    let data = curFile([(dib8(width: 1, height: 1, indices: [1], transparent: [0]), 1, (0, 0))])
    let image = try #require(try WindowsIcon.images(from: data).first).image
    #expect(pixel(image, 0, 0).alphaComponent > 0.99)
    #expect(pixel(image, 0, 0).redComponent < 0.01)
}

@Test func readsPNGEntries() throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 3, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let png = rep.representation(using: .png, properties: [:])!
    let image = try #require(try WindowsIcon.images(from: curFile([(png, 3, (2, 1))])).first)
    #expect(image.image.width == 3)
    #expect(image.hotSpot == CGPoint(x: 2, y: 1))
}

@Test func rejectsOtherFiles() {
    #expect(throws: WindowsCursorError.self) { try WindowsIcon.images(from: Data("not a cursor".utf8)) }
    #expect(throws: WindowsCursorError.self) { try WindowsAni.parse(Data("RIFF....WAVE".utf8)) }
}

@Test func readsAnimationWithSequenceAndRates() throws {
    let frames = [solidCur(size: 4, rgba: [255, 0, 0, 255]), solidCur(size: 4, rgba: [0, 255, 0, 255]),
                  solidCur(size: 4, rgba: [0, 0, 255, 255])]
    let animation = try WindowsAni.parse(aniFile(frames: frames, defaultRate: 5, rates: [2, 4, 2], sequence: [0, 2, 1]))
    #expect(animation.frames.count == 3)
    #expect(animation.steps == [0, 2, 1])
    #expect(animation.rates == [2, 4, 2])
}

@Test func refusesAbsurdStepCounts() throws {
    // A header claiming four billion steps must not become a four-billion-element array.
    let frame = solidCur(size: 4, rgba: [255, 0, 0, 255])
    let file = aniFile(frames: [frame], defaultRate: 6, stepCount: Int(UInt32.max))
    #expect(throws: WindowsCursorError.self) { try WindowsAni.parse(file) }
}

@Test func refusesHugePNGEntries() throws {
    let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2000, pixelsHigh: 2, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let png = try #require(rep.representation(using: .png, properties: [:]))
    let file = curFile([(payload: png, size: 0, hotSpot: (0, 0))])
    #expect(throws: WindowsCursorError.unsupportedImage("2000 × 2 PNG")) { try WindowsIcon.images(from: file) }
}

@Test func ignoresLinksLeavingTheThemeFolder() throws {
    let base = FileManager.default.temporaryDirectory.appending(path: "WinLinks-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: base) }
    let theme = base.appending(path: "theme")
    try FileManager.default.createDirectory(at: theme, withIntermediateDirectories: true)
    try solidCur(size: 4, rgba: [255, 0, 0, 255]).write(to: theme.appending(path: "arrow.cur"))
    try solidCur(size: 4, rgba: [0, 0, 255, 255]).write(to: base.appending(path: "outside.cur"))
    try FileManager.default.createSymbolicLink(atPath: theme.appending(path: "text.cur").path,
                                               withDestinationPath: base.appending(path: "outside.cur").path)
    let loaded = try WindowsCursorTheme.load(folder: theme)
    #expect(Array(loaded.files.keys) == [.arrow])
}

@Test func timesUnevenSteps() {
    // Equal rates: one frame per step.
    let even = WindowsCursor.timeline(steps: [0, 1], rates: [6, 6])
    #expect(even.frames == [0, 1] && even.duration == 0.1 && even.stepDurations == nil)
    // Uneven: repeated in units of the common divisor.
    let uneven = WindowsCursor.timeline(steps: [0, 2, 1], rates: [2, 4, 2])
    #expect(uneven.frames == [0, 2, 2, 1])
    #expect(abs(uneven.duration - 2.0 / 60) < 1e-9)
    #expect(uneven.stepDurations == nil)
    // Too many repeats for the frame limit: average duration, and each step's own kept.
    let long = WindowsCursor.timeline(steps: [0, 1], rates: [1, 40])
    #expect(long.frames == [0, 1])
    #expect(abs(long.duration - 20.5 / 60) < 1e-9)
    #expect(long.stepDurations?.map { ($0 * 60).rounded() } == [1, 40])
}

// MARK: - Converting

@Test func convertsLargeCursorToPoints() throws {
    // 64 px source, hot spot (32, 16) → 32 pt cursor with hot spot (16, 8), at 1x and 2x.
    let cursor = try WindowsCursor.capeCursor(from: solidCur(size: 64, rgba: [255, 0, 0, 255], hotSpot: (32, 16)),
                                              identifier: "com.apple.coregraphics.Arrow")
    #expect(cursor.size == CGSize(width: 32, height: 32))
    #expect(cursor.hotSpot == CGPoint(x: 16, y: 8))
    #expect(cursor.scales == [1, 2])
    #expect(cursor.problems.isEmpty)
}

@Test func convertsAnimation() throws {
    let frames = [solidCur(size: 32, rgba: [255, 0, 0, 255]), solidCur(size: 32, rgba: [0, 0, 255, 255])]
    let cursor = try WindowsCursor.capeCursor(from: aniFile(frames: frames, defaultRate: 6),
                                              identifier: "com.apple.coregraphics.Wait")
    #expect(cursor.frameCount == 2)
    #expect(abs(cursor.frameDuration - 0.1) < 1e-9)
    #expect(cursor.scales == [1])                      // a 32 px source gives no sharper scale
    let images = cursor.frames()
    #expect(pixel(images[0], 16, 16).redComponent > 0.9)
    #expect(pixel(images[1], 16, 16).blueComponent > 0.9)
}

// MARK: - Themes

private let sampleInf = """
[Scheme.Reg]
HKCU,"Control Panel\\Cursors\\Schemes","%SCHEME_NAME%",,"%10%\\%CUR_DIR%\\%pointer%,%10%\\%CUR_DIR%\\%help%"

[Wreg]
HKCU,"Control Panel\\Cursors",Arrow,0x00020000,"%10%\\%CUR_DIR%\\%pointer%"
HKCU,"Control Panel\\Cursors",Wait,0x00020000,"%10%\\%CUR_DIR%\\%busy%"
HKCU,"Control Panel\\Cursors",precisionhair,0x00020000,"%10%\\%CUR_DIR%\\%cross%"
HKCU,"Control Panel\\Cursors",Person,0x00020000,"%10%\\%CUR_DIR%\\%person%"

[Strings]
CUR_DIR     = "Cursors\\Sample"
SCHEME_NAME = "Sample Theme"
pointer     = "Normal.cur"   ; comment
busy        = "Busy.ani"
cross       = "Cross.cur"
person      = "Person.cur"
"""

@Test func readsInstallInf() throws {
    let inf = try #require(InstallInf(data: Data(sampleInf.utf8)))
    #expect(inf.schemeName == "Sample Theme")
    let roles = Dictionary(uniqueKeysWithValues: inf.roles)
    #expect(roles[.arrow] == "Normal.cur")
    #expect(roles[.wait] == "Busy.ani")
    #expect(roles[.crosshair] == "Cross.cur")
    #expect(roles[.person] == "Person.cur")
}

@Test func readsUTF16InfAndSchemeOrder() throws {
    // Only a scheme line: roles come from its order (Arrow, Help, …).
    let text = """
    [Scheme.Reg]
    HKCU,"Control Panel\\Cursors\\Schemes","Ordered",,"C:\\x\\a.cur,C:\\x\\b.cur"
    """
    var data = Data([0xFF, 0xFE])
    data.append(text.data(using: .utf16LittleEndian)!)
    let inf = try #require(InstallInf(data: data))
    let roles = Dictionary(uniqueKeysWithValues: inf.roles)
    #expect(roles[.arrow] == "a.cur")
    #expect(roles[.help] == "b.cur")
}

@Test func guessesRolesFromFileNames() {
    #expect(WindowsCursorRole.guess(fromFileName: "Handwriting.ani") == .nwPen)
    #expect(WindowsCursorRole.guess(fromFileName: "Link.cur") == .hand)
    #expect(WindowsCursorRole.guess(fromFileName: "Diagonal2.ani") == .sizeNESW)
    #expect(WindowsCursorRole.guess(fromFileName: "Normal Select.cur") == .arrow)
    #expect(WindowsCursorRole.guess(fromFileName: "Busy.ani") == .wait)
    #expect(WindowsCursorRole.guess(fromFileName: "readme.cur") == nil)
}

@Test func buildsCapeFromThemeFolder() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "WindowsTheme-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data(sampleInf.utf8).write(to: folder.appending(path: "install.inf"))
    try solidCur(size: 32, rgba: [0, 0, 0, 255]).write(to: folder.appending(path: "normal.CUR"))   // case differs
    try aniFile(frames: [solidCur(size: 32, rgba: [255, 0, 0, 255])], defaultRate: 6)
        .write(to: folder.appending(path: "Busy.ani"))
    try solidCur(size: 32, rgba: [0, 255, 0, 255]).write(to: folder.appending(path: "Cross.cur"))
    try solidCur(size: 32, rgba: [0, 0, 255, 255]).write(to: folder.appending(path: "Person.cur"))

    let theme = try WindowsCursorTheme.load(folder: folder)
    #expect(theme.name == "Sample Theme")
    #expect(theme.files.count == 4)

    let (cape, skipped) = try theme.makeCape(author: "Me")
    #expect(cape.identifier == "local.windows.sampletheme")
    #expect(Set(cape.cursors.map(\.identifier)) == [
        "com.apple.coregraphics.Arrow", "com.apple.coregraphics.Wait",
        "com.apple.cursor.7", "com.apple.cursor.8",
    ])
    #expect(skipped == ["Person Select"])
    #expect(cape.problems.isEmpty)
}

@Test func failsOnFolderWithoutCursors() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "Empty-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(throws: WindowsCursorError.noCursorsFound) { try WindowsCursorTheme.load(folder: folder) }
}
