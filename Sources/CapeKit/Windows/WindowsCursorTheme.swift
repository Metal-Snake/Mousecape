import Foundation

/// The cursor roles of Windows ("Normal Select", "Busy", …), named as in the registry, in
/// the order of a scheme line in `install.inf`.
public enum WindowsCursorRole: String, CaseIterable, Sendable {
    case arrow = "Arrow"
    case help = "Help"
    case appStarting = "AppStarting"
    case wait = "Wait"
    case crosshair = "Crosshair"
    case iBeam = "IBeam"
    case nwPen = "NWPen"
    case no = "No"
    case sizeNS = "SizeNS"
    case sizeWE = "SizeWE"
    case sizeNWSE = "SizeNWSE"
    case sizeNESW = "SizeNESW"
    case sizeAll = "SizeAll"
    case upArrow = "UpArrow"
    case hand = "Hand"
    case pin = "Pin"
    case person = "Person"

    /// The macOS cursors this role stands in for. Empty when macOS has no equivalent.
    public var macIdentifiers: [String] {
        switch self {
        case .arrow: ["com.apple.coregraphics.Arrow"]
        case .help: ["com.apple.cursor.40"]
        case .appStarting: ["com.apple.cursor.4"]                         // Busy
        case .wait: ["com.apple.coregraphics.Wait"]
        case .crosshair: ["com.apple.cursor.7", "com.apple.cursor.8"]
        case .iBeam: ["com.apple.coregraphics.IBeam"]
        case .no: ["com.apple.cursor.3"]                                  // Forbidden
        case .sizeNS: ["com.apple.cursor.23", "com.apple.cursor.32", "com.apple.cursor.21",
                       "com.apple.cursor.22", "com.apple.cursor.31", "com.apple.cursor.36"]
        case .sizeWE: ["com.apple.cursor.19", "com.apple.cursor.28", "com.apple.cursor.17",
                       "com.apple.cursor.18", "com.apple.cursor.27", "com.apple.cursor.38"]
        case .sizeNWSE: ["com.apple.cursor.34", "com.apple.cursor.33", "com.apple.cursor.35"]
        case .sizeNESW: ["com.apple.cursor.30", "com.apple.cursor.29", "com.apple.cursor.37"]
        case .sizeAll: ["com.apple.coregraphics.Move"]
        case .hand: ["com.apple.cursor.13"]                               // Pointing
        case .nwPen, .upArrow, .pin, .person: []
        }
    }

    /// Windows' own name for the role, for messages.
    public var displayName: String {
        switch self {
        case .arrow: "Normal Select"
        case .help: "Help Select"
        case .appStarting: "Working in Background"
        case .wait: "Busy"
        case .crosshair: "Precision Select"
        case .iBeam: "Text Select"
        case .nwPen: "Handwriting"
        case .no: "Unavailable"
        case .sizeNS: "Vertical Resize"
        case .sizeWE: "Horizontal Resize"
        case .sizeNWSE: "Diagonal Resize 1"
        case .sizeNESW: "Diagonal Resize 2"
        case .sizeAll: "Move"
        case .upArrow: "Alternate Select"
        case .hand: "Link Select"
        case .pin: "Location Select"
        case .person: "Person Select"
        }
    }

    /// The role a registry value name stands for (`precisionhair` is an alias of crosshair).
    static func named(_ name: String) -> WindowsCursorRole? {
        let lower = name.lowercased()
        if lower == "precisionhair" { return .crosshair }
        return allCases.first { $0.rawValue.lowercased() == lower }
    }

    /// A guess from a file name, for themes without a usable `install.inf`. More specific
    /// words come first ("handwriting" before "hand").
    public static func guess(fromFileName name: String) -> WindowsCursorRole? {
        let lower = (name as NSString).deletingPathExtension.lowercased()
        let rules: [(WindowsCursorRole, [String])] = [
            (.nwPen, ["handwriting", "nwpen", "pen"]),
            (.appStarting, ["working", "appstarting", "background", "work"]),
            (.sizeNWSE, ["diagonal1", "dgn1", "nwse", "diag1"]),
            (.sizeNESW, ["diagonal2", "dgn2", "nesw", "diag2"]),
            (.sizeNS, ["vertical", "vert", "sizens"]),
            (.sizeWE, ["horizontal", "horz", "sizewe"]),
            (.sizeAll, ["move", "sizeall"]),
            (.upArrow, ["alternate", "uparrow"]),
            (.crosshair, ["precision", "crosshair", "cross"]),
            (.iBeam, ["text", "ibeam", "beam"]),
            (.no, ["unavailable", "forbidden", "no"]),
            (.help, ["help"]),
            (.wait, ["busy", "wait"]),
            (.hand, ["link", "hand"]),
            (.pin, ["location", "pin"]),
            (.person, ["person"]),
            (.arrow, ["normal", "pointer", "arrow", "default"]),
        ]
        // Short words only as a word of their own ("no" must not match "normal").
        let tokens = Set(lower.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        func matches(_ word: String) -> Bool {
            word.count >= 4 ? lower.contains(word) : tokens.contains(word)
        }
        return rules.first { _, words in words.contains(where: matches) }?.0
    }
}

/// A Windows cursor theme: a folder of `.cur`/`.ani` files, usually with an `install.inf`.
public struct WindowsCursorTheme: Sendable {
    public var name: String
    public var files: [WindowsCursorRole: URL]

    public static let fileExtensions: Set<String> = ["cur", "ani", "ico"]

    public init(name: String, files: [WindowsCursorRole: URL]) {
        self.name = name
        self.files = files
    }

    /// Reads the theme in a folder: roles from `install.inf` when there is one, otherwise
    /// guessed from the file names.
    public static func load(folder: URL) throws -> WindowsCursorTheme {
        // Links that point outside the folder are ignored: the theme may come from an archive.
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let contents = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root) }
        // Windows file names are case-insensitive.
        let cursorFiles = Dictionary(
            contents.filter { fileExtensions.contains($0.pathExtension.lowercased()) }
                .map { ($0.lastPathComponent.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first })
        guard !cursorFiles.isEmpty else { throw WindowsCursorError.noCursorsFound }

        var name = folder.lastPathComponent
        var files: [WindowsCursorRole: URL] = [:]
        if let inf = contents.first(where: { $0.pathExtension.lowercased() == "inf" }),
           let parsed = InstallInf(url: inf) {
            if let schemeName = parsed.schemeName, !schemeName.isEmpty { name = schemeName }
            for (role, fileName) in parsed.roles {
                if let url = cursorFiles[fileName.lowercased()] { files[role] = url }
            }
        }
        if files.isEmpty {
            for url in cursorFiles.values.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if let role = WindowsCursorRole.guess(fromFileName: url.lastPathComponent), files[role] == nil {
                    files[role] = url
                }
            }
        }
        guard !files.isEmpty else { throw WindowsCursorError.noCursorsFound }
        return WindowsCursorTheme(name: name, files: files)
    }

    /// A cape with every role that has a macOS equivalent. `skipped` lists the roles left
    /// out (no macOS counterpart, or a file that couldn't be read).
    public func makeCape(author: String) throws -> (cape: Cape, skipped: [String]) {
        var cursors: [CapeCursor] = []
        var skipped: [String] = []
        for role in WindowsCursorRole.allCases {
            guard let url = files[role] else { continue }
            guard !role.macIdentifiers.isEmpty else {
                skipped.append(role.displayName)
                continue
            }
            do {
                let data = try Data(contentsOf: url)
                let cursor = try WindowsCursor.capeCursor(from: data, identifier: role.macIdentifiers[0])
                for identifier in role.macIdentifiers {
                    var copy = cursor
                    copy.identifier = identifier
                    cursors.append(copy)
                }
            } catch {
                skipped.append("\(role.displayName) (\(url.lastPathComponent))")
            }
        }
        guard !cursors.isEmpty else { throw WindowsCursorError.noCursorsFound }
        let slug = name.lowercased().filter { $0.isLetter || $0.isNumber }
        let cape = Cape(identifier: "local.windows.\(slug.isEmpty ? "theme" : slug)",
                        name: name, author: author, version: 1, isHiDPI: true, cursors: cursors)
        return (cape, skipped)
    }
}

/// The parts of a cursor theme's `install.inf` that matter: the scheme name and which file
/// each role uses.
struct InstallInf {
    var schemeName: String?
    var roles: [(WindowsCursorRole, String)] = []

    init?(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }

    init?(data: Data) {
        guard let text = Self.decode(data) else { return nil }
        var sections: [String: [String]] = [:]
        var current = ""
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                current = String(line.dropFirst().dropLast()).lowercased()
                continue
            }
            sections[current, default: []].append(line)
        }

        // [Strings]: key = "value"
        var strings: [String: String] = [:]
        for line in sections["strings"] ?? [] {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            strings[key] = Self.unquote(String(line[line.index(after: equals)...]))
        }
        func expand(_ value: String) -> String {
            var result = value
            for _ in 0..<4 {                                   // nested %vars%, bounded
                var changed = false
                for (key, replacement) in strings {
                    let token = "%\(key)%"
                    if result.range(of: token, options: .caseInsensitive) != nil {
                        result = result.replacingOccurrences(of: token, with: replacement, options: .caseInsensitive)
                        changed = true
                    }
                }
                if !changed { break }
            }
            return result
        }
        func fileName(_ value: String) -> String {
            expand(value).replacingOccurrences(of: "\\", with: "/")
                .components(separatedBy: "/").last?.trimmingCharacters(in: .whitespaces) ?? ""
        }
        schemeName = strings["scheme_name"]

        // Registry lines: HKCU,"Control Panel\Cursors",<Role>,<flags>,"<path>", or the
        // scheme line under "Control Panel\Cursors\Schemes" listing all roles in order.
        var byRole: [WindowsCursorRole: String] = [:]
        var schemeOrder: [String] = []
        for line in sections.values.joined() {
            let fields = Self.csvFields(line)
            guard fields.count >= 5, fields[1].lowercased().hasPrefix("control panel\\cursors") else { continue }
            if fields[1].lowercased().hasSuffix("\\schemes") {
                schemeOrder = expand(fields[4]).components(separatedBy: ",").map(fileName)
            } else if let role = WindowsCursorRole.named(fields[2]) {
                let file = fileName(fields[4])
                if !file.isEmpty { byRole[role] = file }
            }
        }
        if byRole.isEmpty {
            for (role, file) in zip(WindowsCursorRole.allCases, schemeOrder) where !file.isEmpty {
                byRole[role] = file
            }
        }
        roles = WindowsCursorRole.allCases.compactMap { role in byRole[role].map { (role, $0) } }
    }

    /// INF files are often UTF-16 (with a byte order mark), sometimes UTF-8 or a Windows code page.
    private static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
    }

    /// A [Strings] value: the text inside quotes, or up to a `;` comment when unquoted.
    private static func unquote(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\"") {
            let inner = trimmed.dropFirst()
            return String(inner[..<(inner.firstIndex(of: "\"") ?? inner.endIndex)])
        }
        let beforeComment = trimmed.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return beforeComment.trimmingCharacters(in: .whitespaces)
    }

    /// Comma-separated fields; commas inside double quotes don't split.
    static func csvFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var quoted = false
        for character in line {
            if character == "\"" {
                quoted.toggle()
            } else if character == ",", !quoted {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }
}
