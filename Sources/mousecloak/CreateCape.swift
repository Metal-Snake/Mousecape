import AppKit
import CapeKit
import MousecloakCore

/// What `--create` takes from the command line. Everything is optional: a missing cape
/// detail has a default, and the cursors' values come from their images and settings files.
struct CreateOptions {
    var name: String?
    var author: String?
    var identifier: String?
    var version: Double?
    var isHiDPI: Bool?
    /// For every cursor without a hot spot of its own.
    var hotSpot: CGPoint?
    /// For every animated cursor without a frame duration of its own.
    var frameDuration: Double?
}

/// `mousecloak --create`: a cape from a folder of cursor folders (see `CapeFolder`). Asks
/// only about what the images leave open, and only when someone can answer: in a script
/// (no terminal on standard input) it takes the defaults and says so.
func createCape(from inputPath: String, output: String?, options: CreateOptions) {
    let folder = URL(fileURLWithPath: inputPath).standardizedFileURL
    let (drafts, notes): ([CapeFolder.CursorDraft], [String])
    do {
        (drafts, notes) = try CapeFolder.drafts(at: folder)
    } catch {
        fail(error.localizedDescription)
    }
    notes.forEach { print("Note: \($0)") }

    let interactive = isatty(STDIN_FILENO) != 0
    let defaults = CapeFolder.Settings(hotSpot: options.hotSpot, frameDuration: options.frameDuration)
    var cursors: [CapeCursor] = []
    for draft in drafts {
        // The folder's settings file first, then the command line's defaults for all cursors.
        var settings = draft.fileSettings.filled(from: defaults)
        if settings.frameCount == nil && settings.size == nil && !draft.frameCountIsCertain {
            settings.frameCount = askNumber("\(draft.identifier): frames in the \(Int(draft.smallestPixelSize.width))×\(Int(draft.smallestPixelSize.height)) image",
                                            default: draft.guessedFrameCount, interactive: interactive)
        }
        let frames = settings.frameCount ?? draft.guessedFrameCount
        if settings.frameDuration == nil && frames > 1 {
            settings.frameDuration = askNumber("\(draft.identifier): seconds per frame",
                                               default: CapeFolder.defaultFrameDuration, interactive: interactive)
        }
        if settings.hotSpot == nil {
            settings.hotSpot = askPoint("\(draft.identifier): hot spot in points (x,y)", interactive: interactive)
        }
        cursors.append(draft.cursor(with: settings))
    }

    let name = options.name ?? folder.lastPathComponent
    let cape = Cape(identifier: options.identifier ?? CapeFolder.defaultIdentifier(forName: name),
                    name: name, author: options.author ?? NSFullUserName(),
                    version: options.version ?? 1, isHiDPI: options.isHiDPI ?? true, cursors: cursors)
    guard Cape.isValidIdentifier(cape.identifier) else {
        fail("\(cape.identifier) can't be a cape identifier (it becomes a file name)")
    }
    let longAnimations = MCLongAnimationsAvailable()
    for (identifier, problems) in cape.problems(leftHanded: false, longAnimations: longAnimations)
        .sorted(by: { $0.key < $1.key }) {
        for problem in problems { print("Warning: \(identifier): \(problem)") }
    }

    // Default: <folder>.cape next to the folder. A folder as output gets <identifier>.cape.
    var destination = URL(fileURLWithPath: output ?? folder.path + ".cape")
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue {
        destination.append(path: "\(cape.identifier).cape")
    }
    do {
        try cape.propertyListData().write(to: destination, options: .atomic)
    } catch {
        fail("could not write \(destination.path): \(error.localizedDescription)")
    }
    print("Cape \"\(cape.name)\" with \(cursors.count) cursors written to \(destination.path)")
}

/// A number from the user, or `defaultValue` when the line is empty or no one can answer.
private func askNumber<Number: LosslessStringConvertible>(_ question: String, default defaultValue: Number,
                                                          interactive: Bool) -> Number {
    guard interactive else {
        print("\(question): \(defaultValue) (default)")
        return defaultValue
    }
    while true {
        print("\(question) [\(defaultValue)]: ", terminator: "")
        fflush(stdout)      // the question has no line break, so it would wait in the buffer
        guard let line = readLine()?.trimmingCharacters(in: .whitespaces) else { return defaultValue }
        if line.isEmpty { return defaultValue }
        if let number = Number(line) { return number }
        print("Please enter a number.")
    }
}

/// A point "x,y" from the user, or (0, 0) when the line is empty or no one can answer.
private func askPoint(_ question: String, interactive: Bool) -> CGPoint {
    guard interactive else {
        print("\(question): 0,0 (default)")
        return .zero
    }
    while true {
        print("\(question) [0,0]: ", terminator: "")
        fflush(stdout)      // the question has no line break, so it would wait in the buffer
        guard let line = readLine()?.trimmingCharacters(in: .whitespaces) else { return .zero }
        if line.isEmpty { return .zero }
        if let point = parsePoint(line) { return point }
        print("Please enter two numbers, such as 4,4.")
    }
}

/// "x,y" with two numbers of at least 0; nil otherwise.
func parsePoint(_ text: String) -> CGPoint? {
    let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]), x >= 0, y >= 0 else { return nil }
    return CGPoint(x: x, y: y)
}
