import AppKit
import CapeKit
import LoginAgentKit
import MousecloakCore

// mousecloak: the command line front end of the cursor engine. Same options as the
// original GBCli-based tool; `--listen` is what the background agent runs.

let usage = """
mousecloak — apply and manage Mousecape cursors

APPLYING CAPES
  -a, --apply <cape>      Apply a cape
  -r, --reset             Reset to the default macOS cursors (mirrored in left-handed mode)
CREATING CAPES
  -c, --create <dir>      Create a cape from a folder of <cursor identifier>/<images>
                          (one image per scale, frames stacked; see "Creating" below)
  -d, --dump <file>       Dump the currently applied cursors to a cape file
  -x, --convert <file>    Convert a .MightyMouse file to a cape
MISCELLANEOUS
  -e, --export <cape>     Export a cape to a directory (requires -o)
  -o, --output <path>     Output for --create, --convert and --export
  -s, --scale [value]     Get, or set, the cursor scale
      --listen            Stay alive and re-apply the current cape on login and display changes
      --list              Show which cursors are registered, and their backups (for bug reports)
      --repair-agent      Set up the background agent again if it is turned on in Settings
                          but missing or outdated (Homebrew's cask runs this after installing)
  -h, --help              Show this help

CREATING
  Options for --create; all are optional:
      --name <name>          Cape name (default: the folder's name)
      --author <author>      Author (default: your full name)
      --identifier <id>      Cape identifier (default: local.<name>)
      --cape-version <n>     Cape version (default: 1)
      --hidpi, --no-hidpi    Whether the cape has HiDPI images (default: --hidpi)
      --hot-spot <x,y>       Hot spot for cursors without their own (default: 0,0)
      --frame-duration <s>   Seconds per frame for animations without their own (default: 0.1)
  The smallest image of a cursor is taken as 1x and gives its size; a sheet as tall as a
  multiple of its width holds that many square frames. A cursor.plist in a cursor's folder
  (keys HotSpotX, HotSpotY, PointsWide, PointsHigh, FrameCount, FrameDuration) overrides
  this. Values the images leave open are asked for in a terminal; in a script the defaults
  are taken. Without -o, the cape is written next to the folder as <folder>.cape.
"""

enum Command {
    case apply(String), reset, create(String), convert(String), dump(String)
    case export(String), scale(Float?), listen, list, repairAgent, help
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("mousecloak: \(message)\n".utf8))
    exit(EXIT_FAILURE)
}

func parse(_ args: [String]) -> (Command, output: String?, create: CreateOptions) {
    var commands: [Command] = []
    var output: String?
    var create = CreateOptions()
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
        case "--name": create.name = value(for: arg)
        case "--author": create.author = value(for: arg)
        case "--identifier": create.identifier = value(for: arg)
        case "--cape-version":
            guard let version = Double(value(for: arg)) else { fail("--cape-version needs a number") }
            create.version = version
        case "--hidpi": create.isHiDPI = true
        case "--no-hidpi": create.isHiDPI = false
        case "--hot-spot":
            guard let point = parsePoint(value(for: arg)) else { fail("--hot-spot needs two numbers, such as 4,4") }
            create.hotSpot = point
        case "--frame-duration":
            guard let duration = Double(value(for: arg)), duration > 0 else { fail("--frame-duration needs a positive number") }
            create.frameDuration = duration
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
        case "--repair-agent": commands.append(.repairAgent)
        case "-h", "-?", "--help": commands.append(.help)
        case "--suppressCopyright": break   // accepted for compatibility with older agents
        default: fail("unknown option \(arg), try --help")
        }
        i += 1
    }
    if commands.count > 1 { fail("one command at a time") }
    return (commands.first ?? .help, output, create)
}

let (command, output, createOptions) = parse(Array(CommandLine.arguments.dropFirst()))

switch command {
case .help:
    print(usage)
case .apply(let path):
    if !applyCapeAtPath(path) { exit(EXIT_FAILURE) }
case .reset:
    // The macOS cursors, mirrored when left-handed mode is on.
    if !applyDefaultCursors() { exit(EXIT_FAILURE) }
case .create(let input):
    createCape(from: input, output: output, options: createOptions)
case .convert(let input):
    // Default: <file>.cape next to the MightyMouse file.
    let destination = output ?? (input as NSString).deletingPathExtension + ".cape"
    if let error = convertMightyMouseFile(input, destination) {
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
case .repairAgent:
    // Homebrew removes the agent's plist on every upgrade, not only on uninstall; this puts
    // it back, running this copy and build of the app, when the user has it turned on.
    // Homebrew runs it in a sandbox that may not load launch agents; the plist is written
    // all the same, so launchd starts the agent at the next login, and the app loads it
    // when it next opens.
    guard let agent = LaunchAgent.current else { fail("--repair-agent only works from inside Mousecape.app") }
    do {
        if try agent.repairIfNeeded() {
            print("Background agent set up for \(agent.appURL.path)")
        } else {
            print(agent.isEnabled ? "Background agent is up to date" : "Background agent is turned off in Settings")
        }
    } catch LaunchAgent.AgentError.launchctl {
        print("Background agent set up for \(agent.appURL.path); it starts at the next login, or when Mousecape opens")
    } catch {
        fail(error.localizedDescription)
    }
case .listen:
    // mousecloak lives inside Mousecape.app, so once the engine loads Cocoa the system
    // takes the agent for the app itself: a Dock icon that bounces forever. Declare it a
    // background process first.
    NSApplication.shared.setActivationPolicy(.prohibited)
    // The agent's output goes to a log file; write it line by line instead of when the
    // (never-ending) process exits.
    setvbuf(stdout, nil, _IOLBF, 0)
    print("mousecloak agent started \(Date())")
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
    // The window server's own names for its cursors; newer macOS versions add variants.
    let systemNames = (0..<128).compactMap { index -> String? in
        guard let name = CGSCursorNameForSystemCursor(CGSCursorID(index)) else { return nil }
        let string = String(cString: name)
        return string.isEmpty ? nil : string
    }
    print("System cursors: \(systemNames.map { $0.replacingOccurrences(of: "com.apple.coregraphics.", with: "") }.joined(separator: ", "))")
    print("")
    let names = Set(CursorNames.all.keys).union(extras).union(systemNames)
        .filter { !$0.hasPrefix("com.apple.cursor.") }       // core cursors live elsewhere
        .sorted()
    func describe(_ info: (size: CGSize, frames: Int, pixels: [CGSize], hotSpot: CGPoint)?) -> String {
        guard let info else { return "-" }
        let pixels = info.pixels.map { "\(Int($0.width))x\(Int($0.height))" }.joined(separator: " ")
        // Locale-independent: "4,5" for 4.5 would make "@4,5,4" unreadable.
        let hot = String(format: "@(%g, %g)", locale: Locale(identifier: "en_US_POSIX"),
                         Double(info.hotSpot.x), Double(info.hotSpot.y))
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
