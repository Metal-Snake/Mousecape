import CoreGraphics
import Foundation

// Unregister probe: checks whether a process can remove a cursor that another process
// registered (NOTES.md, "Registrations last for the session"). It registers a test cursor
// in a child process that then exits, and tries to remove it from this process, first with
// the non-global flag the engine uses, then with the global one. The test cursor has a name
// of its own, so no system or cape cursor is touched.
//
// Usage: swiftc -o /tmp/unregister-probe Scripts/unregister-probe.swift && /tmp/unregister-probe
// (compiled, because the probe starts itself again as the child process)

@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSRegisterCursorWithImages")
func CGSRegisterCursorWithImages(_ cid: Int32, _ name: UnsafePointer<CChar>, _ global: Bool, _ instantly: Bool,
                                 _ size: CGSize, _ hotSpot: CGPoint, _ frameCount: Int32, _ frameDuration: CGFloat,
                                 _ images: CFArray, _ seed: UnsafeMutablePointer<Int32>) -> Int32
@_silgen_name("CGSRemoveRegisteredCursor")
func CGSRemoveRegisteredCursor(_ cid: Int32, _ name: UnsafePointer<CChar>, _ global: Bool) -> Int32
@_silgen_name("CGSGetRegisteredCursorDataSize")
func CGSGetRegisteredCursorDataSize(_ cid: Int32, _ name: UnsafePointer<CChar>, _ size: UnsafeMutablePointer<Int>) -> Int32

func isRegistered(_ name: String) -> Bool {
    var size = 0
    return CGSGetRegisteredCursorDataSize(CGSMainConnectionID(), name, &size) == 0 && size > 0
}

func register(_ name: String) -> Bool {
    let ctx = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    var seed: Int32 = 0
    // Global, as the engine registers cursors and backups.
    return CGSRegisterCursorWithImages(CGSMainConnectionID(), name, true, true, CGSize(width: 16, height: 16),
                                       .zero, 1, 1, [ctx.makeImage()!] as CFArray, &seed) == 0
        && isRegistered(name)
}

let arguments = CommandLine.arguments
if arguments.count == 3, arguments[1] == "--register" {
    exit(register(arguments[2]) ? 0 : 1)
}

let name = "io.github.metal-snake.unregister-probe.\(getpid())"
let child = Process()
child.executableURL = URL(fileURLWithPath: Bundle.main.executablePath ?? arguments[0])
child.arguments = ["--register", name]
try child.run()
child.waitUntilExit()
guard child.terminationStatus == 0, isRegistered(name) else {
    print("The child process could not register \(name).")
    exit(1)
}
print("Registered by another process, which has exited: \(name)")

for global in [false, true] {
    let error = CGSRemoveRegisteredCursor(CGSMainConnectionID(), name, global)
    print("Remove with global = \(global): error \(error), still registered: \(isRegistered(name))")
    if !isRegistered(name) { break }
}
