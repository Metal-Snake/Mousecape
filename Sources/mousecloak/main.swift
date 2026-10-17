import AppKit
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
  -h, --help              Show this help
"""

enum Command {
    case apply(String), reset, create(String), convert(String), dump(String)
    case export(String), scale(Float?), listen, help
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
    resetAllCursors()
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
case .listen:
    // mousecloak lives inside Mousecape.app, so once the engine loads Cocoa the system
    // takes the agent for the app itself: a Dock icon that bounces forever. Declare it a
    // background process first.
    NSApplication.shared.setActivationPolicy(.prohibited)
    listener()
}
