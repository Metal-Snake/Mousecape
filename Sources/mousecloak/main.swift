import AppKit
import CapeKit
import MousecloakCore

// mousecloak: the command line front end of the cursor engine. Same options as the
// original GBCli-based tool; `--listen` is what the background agent runs.

let usage = """
mousecloak — apply and manage Mousecape cursors

APPLYING CAPES
  -a, --apply <cape>      Apply a cape
  -r, --reset             Reset to the default macOS cursors
CREATING CAPES
  -c, --create <dir>      Create a cape from a folder of <cursor identifier>/<n>.png
  -d, --dump <file>       Dump the currently applied cursors to a cape file
  -x, --convert <file>    Convert a .MightyMouse file to a cape
MISCELLANEOUS
  -e, --export <cape>     Export a cape to a directory (requires -o)
  -o, --output <path>     Output for --create, --convert and --export
  -s, --scale [value]     Get, or set, the cursor scale
      --listen            Stay alive and re-apply the current cape on login and display changes
      --list              Show which cursors are registered, and their backups (for bug reports)
  -h, --help              Show this help
"""

enum Command {
    case apply(String), reset, create(String), convert(String), dump(String)
    case export(String), scale(Float?), listen, list, help
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("mousecloak: \(message)\n".utf8))
    exit(EXIT_FAILURE)
}

func parse(_ args: [String]) -> (Command, output: String?) {
    var commands: [Command] = []
    var output: String?
    var i = 0
    func value(for option: String) -> String {
        i += 1
        guard i < args.count else { fail("missing value for \(option), try --help") }
        return args[i]
    }
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "-a", "--apply": commands.append(.apply(value(for: arg)))
        case "-r", "--reset": commands.append(.reset)
        case "-c", "--create": commands.append(.create(value(for: arg)))
        case "-x", "--convert": commands.append(.convert(value(for: arg)))
        case "-d", "--dump": commands.append(.dump(value(for: arg)))
        case "-e", "--export": commands.append(.export(value(for: arg)))
        case "-o", "--output": output = value(for: arg)
        case "-s", "--scale":
            // The value is optional: `--scale` alone prints the current scale.
            if i + 1 < args.count, let scale = Float(args[i + 1]) {
                i += 1
                commands.append(.scale(scale))
            } else {
                commands.append(.scale(nil))
            }
        case "--listen": commands.append(.listen)
        case "--list": commands.append(.list)
        case "-h", "-?", "--help": commands.append(.help)
        case "--suppressCopyright": break   // accepted for compatibility with older agents
        default: fail("unknown option \(arg), try --help")
        }
        i += 1
    }
    if commands.count > 1 { fail("one command at a time") }
    return (commands.first ?? .help, output)
}

let (command, output) = parse(Array(CommandLine.arguments.dropFirst()))

switch command {
case .help:
    print(usage)
case .apply(let path):
    if !applyCapeAtPath(path) { exit(EXIT_FAILURE) }
case .reset:
    if !resetAllCursors() { exit(EXIT_FAILURE) }
case .create(let input), .convert(let input):
    var isConvert = false
    if case .convert = command { isConvert = true }
    let destination = output ?? (input as NSString).deletingLastPathComponent
    if let error = createCape(input, destination, isConvert) {
        fail(error.localizedDescription)
    }
    print("Cape written to \(destination)")
case .export(let input):
    guard let output else { fail("--export needs an output directory, use -o") }
    guard let cape = NSDictionary(contentsOfFile: input) as? [AnyHashable: Any] else {
        fail("could not read a cape at \(input)")
    }
    exportCape(cape, output)
case .dump(let path):
    let ok = dumpCursorsToFile(path) { current, total in
        print("Dumped \(current) of \(total)")
        return true
    }
    if !ok { exit(EXIT_FAILURE) }
case .scale(let value):
    if let value {
        if !setCursorScale(value) { exit(EXIT_FAILURE) }
    } else {
        print(cursorScale())
    }
case .list:
    listRegisteredCursors()
case .listen:
    // mousecloak lives inside Mousecape.app, so once the engine loads Cocoa the system
    // takes the agent for the app itself: a Dock icon that bounces forever. Declare it a
    // background process first.
    NSApplication.shared.setActivationPolicy(.prohibited)
    listener()
}

// MARK: - --list

/// What the window server has registered under a cursor name.
func registration(of name: String) -> (size: CGSize, frames: Int, pixels: [CGSize], hotSpot: CGPoint)? {
    name.withCString { cName in
        let cursorName = UnsafeMutablePointer(mutating: cName)
        var registered = false
        MCIsCursorRegistered(CGSMainConnectionID(), cursorName, &registered)
        guard registered else { return nil }
        var size = CGSize.zero, hotSpot = CGPoint.zero, duration: CGFloat = 0
        var frames: UInt = 0
        var images: Unmanaged<CFArray>?
        guard CGSCopyRegisteredCursorImages(CGSMainConnectionID(), cursorName, &size, &hotSpot,
                                            &frames, &duration, &images) == .success else {
            return (.zero, 0, [], .zero)
        }
        let array = images?.takeRetainedValue() as? [CGImage] ?? []
        return (size, Int(frames), array.map { CGSize(width: $0.width, height: $0.height) }, hotSpot)
    }
}

func listRegisteredCursors() {
    let applied = (CFPreferencesCopyAppValue("MCAppliedCursor" as CFString,
                                             "com.alexzielenski.Mousecape" as CFString) as? String) ?? "none"
    let extras = (CFPreferencesCopyAppValue("MCAppliedExtraCursors" as CFString,
                                            "com.alexzielenski.Mousecape" as CFString) as? [String]) ?? []
    print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("Applied cape: \(applied)")
    print("Cursor scale: \(cursorScale())")
    let leftHanded = (CFPreferencesCopyAppValue("MCHandedness" as CFString,
                                                "com.alexzielenski.Mousecape" as CFString) as? Bool) ?? false
    print("Left-handed: \(leftHanded ? "on" : "off")")
    print("")
    let names = Set(CursorNames.all.keys).union(extras)
        .filter { !$0.hasPrefix("com.apple.cursor.") }       // core cursors live elsewhere
        .sorted()
    func describe(_ info: (size: CGSize, frames: Int, pixels: [CGSize], hotSpot: CGPoint)?) -> String {
        guard let info else { return "-" }
        let pixels = info.pixels.map { "\(Int($0.width))x\(Int($0.height))" }.joined(separator: " ")
        let hot = "@\(info.hotSpot.x.formatted()),\(info.hotSpot.y.formatted())"
        return "\(Int(info.size.width))x\(Int(info.size.height)) pt \(hot), \(info.frames) fr [\(pixels)]"
    }
    let width = names.map(\.count).max() ?? 30
    print("\("cursor".padding(toLength: width, withPad: " ", startingAt: 0))  registered | backup")
    for name in names {
        let current = describe(registration(of: name))
        let backup = describe(registration(of: "com.alexzielenski.mousecape." + name))
        print("\(name.padding(toLength: width, withPad: " ", startingAt: 0))  \(current) | \(backup)")
    }
}
