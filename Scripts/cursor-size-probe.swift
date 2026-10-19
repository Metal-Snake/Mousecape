import AppKit
import ScreenCaptureKit

// Cursor size probe: applies test capes (red rectangles of known size) with mousecloak and
// prints the size macOS really draws them at, captured with ScreenCaptureKit
// (`screencapture -C` shows no cursor on newer macOS). Afterwards the previously applied
// cape is applied again.
//
// The probe opens a small white window under the mouse and becomes the active app, so the
// arrow is the cursor there and nothing else on screen interferes. macOS doesn't redraw the
// cursor just because a registered image changed, so after each apply the probe sets the
// arrow again and nudges the cursor scale (as the agent does, a private call looked up at
// run time).
//
// Usage: swift Scripts/cursor-size-probe.swift [path to Mousecape.app]
//        (or compile it with swiftc and sign it to run it on a Mac without the toolchain)
// Needs Screen Recording permission. Don't move the mouse while it runs. In a virtual
// machine, copy it out of a shared folder first: macOS kills it when run from there.

let app = CommandLine.arguments.dropFirst().first ?? "/Applications/Mousecape.app"
let mousecloak = app + "/Contents/MacOS/mousecloak"
let folder = FileManager.default.temporaryDirectory.appending(path: "mousecape-sizeprobe")
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

@discardableResult
func run(_ arguments: [String]) -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: mousecloak); p.arguments = arguments
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
    try? p.run(); p.waitUntilExit()
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
}

// MARK: - Test capes

func png(_ w: Int, _ h: Int) -> Data {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

/// A cape whose arrow (and the arrow variant of newer macOS) is a red rectangle with the
/// hot spot in its top-left corner.
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

// MARK: - Cursor

private let handle = dlopen(nil, RTLD_NOW)
private func symbol<T>(_ name: String, as type: T.Type) -> T? {
    dlsym(handle, name).map { unsafeBitCast($0, to: type) }
}
private let mainConnection = symbol("CGSMainConnectionID", as: (@convention(c) () -> Int32).self)
private let getCursorScale = symbol("CGSGetCursorScale", as: (@convention(c) (Int32, UnsafeMutablePointer<Float>) -> Int32).self)
private let setCursorScale = symbol("CGSSetCursorScale", as: (@convention(c) (Int32, Float) -> Int32).self)

/// A white view that shows the arrow.
final class ArrowView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

/// Makes the window server draw the (newly registered) arrow now.
@MainActor func refreshCursor(in window: NSWindow) async {
    window.invalidateCursorRects(for: window.contentView!)
    NSCursor.arrow.set()
    if let connection = mainConnection?() {
        var scale: Float = 1
        if getCursorScale?(connection, &scale) == 0 {
            _ = setCursorScale?(connection, scale + 0.3)
            try? await Task.sleep(for: .milliseconds(150))
            _ = setCursorScale?(connection, scale)
        }
    }
    NSCursor.arrow.set()
    try? await Task.sleep(for: .milliseconds(600))
}

// MARK: - Measuring

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

/// The red rectangle drawn at the mouse, in points: the connected red area that touches
/// the mouse position (the hot spot is in a corner: top left, top right in left-handed mode).
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
    let reach = Int(2 * scale)
    var seed: (Int, Int)?
    search: for dy in -reach...reach { for dx in -reach...reach {
        let x = mx + dx, y = my + dy
        if x >= 0, y >= 0, x < w, y < h, isRed(x, y) { seed = (x, y); break search }
    } }
    guard let seed else { return "no red cursor at the mouse" }
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

// MARK: - Run

let sizes: [(Int, Int, [Int])] = [(17, 23, [1, 2]), (24, 24, [1, 2]), (32, 32, [1, 2]), (33, 33, [1, 2]),
                                   (28, 40, [1, 2]), (28, 36, [1, 2]), (48, 48, [1, 2]), (48, 48, [1]),
                                   (64, 64, [1, 2]), (40, 20, [1, 2]), (24, 48, [1, 2])]

@MainActor func probe() async {
    let previous = CFPreferencesCopyAppValue("MCAppliedCursor" as CFString, "com.alexzielenski.Mousecape" as CFString) as? String
    print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString), main display scale \(NSScreen.main?.backingScaleFactor ?? 0)")
    print("Cursor scale: \(run(["--scale"]).trimmingCharacters(in: .whitespacesAndNewlines))")
    print("Cursor scale nudge: \(setCursorScale != nil ? "available" : "MISSING (results may be stale)")")
    print("Don't move the mouse while this runs.\n")

    // A white window under the mouse (AppKit coordinates: origin bottom left).
    let mouse = NSEvent.mouseLocation
    let window = NSWindow(contentRect: NSRect(x: mouse.x - 150, y: mouse.y - 150, width: 300, height: 300),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = ArrowView()
    window.level = .floating
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    try? await Task.sleep(for: .milliseconds(500))

    print("registered          ->  drawn")
    var last = ""
    for (w, h, scales) in sizes {
        run(["--apply", makeCape(w, h, scales: scales).path])
        await refreshCursor(in: window)
        let label = "\(w) x \(h) pt (\(scales.map { "\($0)x" }.joined(separator: ",")))"
        var drawn: String
        do {
            drawn = measure(try await capture())
            if drawn == last || drawn.hasPrefix("no red") {                  // give it another chance
                await refreshCursor(in: window)
                drawn = measure(try await capture())
            }
        } catch {
            drawn = "capture failed: \(error.localizedDescription)"
        }
        print(label.padding(toLength: 20, withPad: " ", startingAt: 0), "-> ", drawn)
        last = drawn
    }
    window.orderOut(nil)

    if let previous {
        let cape = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Mousecape/capes/\(previous).cape")
        run(["--apply", cape.path])
        print("\nRe-applied \(previous).")
    } else {
        run(["--reset"])
        print("\nNo cape was applied before; reset to the macOS cursors.")
    }
    NSApp.terminate(nil)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
Task { @MainActor in await probe() }
application.run()
