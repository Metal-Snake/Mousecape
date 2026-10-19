import AppKit
import ScreenCaptureKit

// Cursor size probe: applies test capes (red rectangles of known size) with mousecloak,
// captures the screen with the cursor through ScreenCaptureKit (`screencapture -C` doesn't
// show custom cursors), and prints the size macOS really draws. Afterwards the previously
// applied cape is applied again.
//
// Usage: swift Scripts/cursor-size-probe.swift [--auto] [path to Mousecape.app]
//        (or compile it with swiftc to run it on another Mac without the toolchain)
// Needs Screen Recording permission. macOS only redraws the cursor when the mouse moves, so
// for each size the probe asks you to move the mouse a little and measures once it's still
// again. With --auto it moves the mouse itself (needs Accessibility permission, and you
// mustn't touch the mouse meanwhile).

let options = CommandLine.arguments.dropFirst()
let auto = options.contains("--auto")
let app = options.first { $0 != "--auto" } ?? "/Applications/Mousecape.app"
let mousecloak = app + "/Contents/MacOS/mousecloak"
let folder = FileManager.default.temporaryDirectory.appending(path: "mousecape-sizeprobe")
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

func run(_ arguments: [String]) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: mousecloak); p.arguments = arguments
    p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
    try? p.run(); p.waitUntilExit()
}

func png(_ w: Int, _ h: Int) -> Data {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

func makeCape(_ w: Int, _ h: Int, scales: [Int]) -> URL {
    let cursor: [String: Any] = ["FrameCount": 1, "FrameDuration": 1.0, "HotSpotX": 0.0, "HotSpotY": 0.0,
                                 "PointsWide": Double(w), "PointsHigh": Double(h),
                                 "Representations": scales.map { png(w * $0, h * $0) }]
    var cursors: [String: Any] = [:]
    for id in ["com.apple.coregraphics.Arrow", "com.apple.coregraphics.ArrowS"] { cursors[id] = cursor }
    let cape: [String: Any] = ["Version": 2.0, "MinimumVersion": 2.0, "Identifier": "local.sizeprobe.\(w)x\(h)",
                               "CapeName": "Probe \(w)x\(h)", "Author": "Probe", "CapeVersion": 1.0, "HiDPI": true,
                               "Cloud": false, "Cursors": cursors]
    let url = folder.appending(path: "probe-\(w)x\(h)-\(scales.map(String.init).joined()).cape")
    try! PropertyListSerialization.data(fromPropertyList: cape, format: .binary, options: 0).write(to: url)
    return url
}

func run(capturing arguments: [String]) -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: mousecloak); p.arguments = arguments
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
    try? p.run(); p.waitUntilExit()
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
}

let canPostEvents = auto && AXIsProcessTrusted()

func mouseLocation() -> CGPoint { CGEvent(source: nil)!.location }

/// Waits until the mouse has moved and then stood still for a moment (15 s at most).
func waitForMoveAndRest() {
    let start = mouseLocation()
    var moved = false, lastMove = Date(), last = start
    let deadline = Date().addingTimeInterval(15)
    while Date() < deadline {
        usleep(50_000)
        let now = mouseLocation()
        if now != last { moved = true; lastMove = Date(); last = now }
        if moved && Date().timeIntervalSince(lastMove) > 0.8 { return }
    }
}

/// Gets macOS to redraw the cursor: it only does that when the mouse moves.
func refreshCursor() {
    if canPostEvents {
        sleep(1); jiggle(); sleep(1)
    } else {
        print("   move the mouse a little, then hold it still …", terminator: "")
        fflush(stdout)
        waitForMoveAndRest()
        print("\r", terminator: "")
    }
}

func jiggle() {
    let p = CGEvent(source: nil)!.location
    for dx in [6.0, 0.0] {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: p.x + dx, y: p.y),
                mouseButton: .left)!.post(tap: .cghidEventTap)
        usleep(200_000)
    }
}

func capture() async throws -> CGImage {
    let content = try await SCShareableContent.current
    let display = content.displays.first { $0.displayID == CGMainDisplayID() }!
    let filter = SCContentFilter(display: display, excludingWindows: [])
    let config = SCStreamConfiguration()
    let scale = Int(filter.pointPixelScale)
    config.width = display.width * scale
    config.height = display.height * scale
    config.showsCursor = true
    return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
}

/// The red rectangle drawn at the mouse, in points. The test cursors have their hot spot in
/// a corner (top left, top right in left-handed mode), so the cursor is the connected red
/// area that touches the mouse position; other red things on screen don't count.
func measure(_ image: CGImage) -> String {
    let w = image.width, h = image.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    func isRed(_ x: Int, _ y: Int) -> Bool {
        let i = (y * w + x) * 4
        return pixels[i] > 200 && pixels[i + 1] < 60 && pixels[i + 2] < 60
    }
    let screen = CGDisplayBounds(CGMainDisplayID())
    let scale = Double(w) / screen.width
    let mouse = CGEvent(source: nil)!.location
    let mx = Int((mouse.x - screen.minX) * scale), my = Int((mouse.y - screen.minY) * scale)
    // A red pixel within 2 points of the mouse to start from.
    let reach = Int(2 * scale)
    var seed: (Int, Int)?
    search: for dy in -reach...reach { for dx in -reach...reach {
        let x = mx + dx, y = my + dy
        if x >= 0, y >= 0, x < w, y < h, isRed(x, y) { seed = (x, y); break search }
    } }
    guard let seed else { return "no red cursor at the mouse (not redrawn? Screen Recording allowed?)" }
    // Flood fill the connected red area.
    var seen = Set<Int>([seed.1 * w + seed.0])
    var stack = [seed]
    var minX = seed.0, maxX = seed.0, minY = seed.1, maxY = seed.1
    while let (x, y) = stack.popLast() {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
        where nx >= 0 && ny >= 0 && nx < w && ny < h && isRed(nx, ny) && seen.insert(ny * w + nx).inserted {
            stack.append((nx, ny))
        }
    }
    return String(format: "%.0f x %.0f pt", Double(maxX - minX + 1) / scale, Double(maxY - minY + 1) / scale)
}

let previous = CFPreferencesCopyAppValue("MCAppliedCursor" as CFString, "com.alexzielenski.Mousecape" as CFString) as? String
print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString), main display scale \(NSScreen.main?.backingScaleFactor ?? 0)")
print("Cursor scale: \(run(capturing: ["--scale"]).trimmingCharacters(in: .whitespacesAndNewlines))")
if auto && !canPostEvents { print("--auto needs Accessibility permission; moving the mouse is up to you.") }
print(canPostEvents ? "Don't touch the mouse while this runs.\n"
                    : "For each size, move the mouse a little and hold it still over an empty area.\n")
print("registered          ->  drawn")
let allSizes: [(Int, Int, [Int])] = [(17, 23, [1, 2]), (24, 24, [1, 2]), (32, 32, [1, 2]), (33, 33, [1, 2]),
                                      (28, 40, [1, 2]), (28, 36, [1, 2]), (48, 48, [1, 2]), (48, 48, [1]),
                                      (64, 64, [1, 2]), (40, 20, [1, 2]), (24, 48, [1, 2])]
let sizes = ProcessInfo.processInfo.environment["SIZEPROBE_QUICK"] != nil ? Array(allSizes.prefix(2)) : allSizes
let done = DispatchSemaphore(value: 0)
nonisolated(unsafe) var previousResult = ""
nonisolated(unsafe) var previousSize = (0, 0)
Task {
    for (w, h, scales) in sizes {
        run(["--apply", makeCape(w, h, scales: scales).path])
        refreshCursor()
        let label = "\(w) x \(h) pt (\(scales.map { "\($0)x" }.joined(separator: ",")))"
        do {
            var image = try await capture()
            if measure(image).hasPrefix("no red") {                 // the first switch can be slow
                refreshCursor()
                image = try await capture()
            }
            if let dump = ProcessInfo.processInfo.environment["SIZEPROBE_DUMP"] {
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: "\(dump)/\(w)x\(h).png"))
            }
            let drawn = measure(image)
            // The same result as the size before (when that was different) means the cursor
            // wasn't redrawn.
            let stale = drawn == previousResult && (w, h) != previousSize ? "   (unchanged: not redrawn?)" : ""
            print(label.padding(toLength: 20, withPad: " ", startingAt: 0), "-> ", drawn + stale)
            previousResult = drawn; previousSize = (w, h)
        } catch {
            print(label, "-> capture failed: \(error.localizedDescription)")
        }
    }
    done.signal()
}
done.wait()
if let previous {
    let cape = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Mousecape/capes/\(previous).cape")
    run(["--apply", cape.path])
    print("\nRe-applied \(previous).")
} else {
    run(["--reset"])
    print("\nNo cape was applied before; reset to the macOS cursors.")
}
