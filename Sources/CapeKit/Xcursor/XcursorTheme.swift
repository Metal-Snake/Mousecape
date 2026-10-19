import Foundation

/// A cursor theme an importer turns into a cape (Windows or Xcursor).
public protocol CursorThemeConvertible: Sendable {
    var name: String { get set }
    /// A cape with every cursor that has a macOS counterpart; `skipped` names what was left
    /// out (no counterpart, or a file that couldn't be read).
    func makeCape(author: String) throws -> (cape: Cape, skipped: [String])
}

extension WindowsCursorTheme: CursorThemeConvertible {}

/// An Xcursor theme (X11 and Wayland desktops): a folder with an `index.theme` and a
/// `cursors` folder of Xcursor files named after the cursor (`left_ptr`, `xterm`, …),
/// many of them symbolic links to others.
public struct XcursorTheme: CursorThemeConvertible {
    public var name: String
    /// Xcursor files by cursor name.
    public var files: [String: URL]

    public init(name: String, files: [String: URL]) {
        self.name = name
        self.files = files
    }

    /// The macOS cursors and the Xcursor names that stand for them, best match first. Themes
    /// carry the CSS names (`pointer`, `ew-resize`), the old X11 names (`hand2`,
    /// `sb_h_double_arrow`) or both. macOS cursors without a counterpart (the counting hands,
    /// Poof, the screenshot cursors, the legacy placeholders) are left out.
    public static let macNames: [(identifier: String, names: [String])] = [
        ("com.apple.coregraphics.Arrow", ["default", "left_ptr", "arrow", "top_left_arrow"]),
        ("com.apple.coregraphics.IBeam", ["text", "xterm", "ibeam"]),
        ("com.apple.coregraphics.Wait", ["wait", "watch"]),
        ("com.apple.coregraphics.Move", ["move", "fleur", "all-scroll", "size_all"]),
        ("com.apple.cursor.2", ["alias", "dnd-link", "link"]),                        // Make Alias
        ("com.apple.cursor.3", ["not-allowed", "crossed_circle", "forbidden", "no-drop", "dnd-no-drop", "circle"]),
        ("com.apple.cursor.4", ["progress", "left_ptr_watch", "half-busy"]),          // Busy but Clickable
        ("com.apple.cursor.5", ["copy", "dnd-copy"]),
        ("com.apple.cursor.7", ["crosshair", "cross", "tcross"]),
        ("com.apple.cursor.8", ["crosshair", "cross", "tcross"]),
        ("com.apple.cursor.11", ["grabbing", "closedhand", "dnd-move", "fist"]),
        ("com.apple.cursor.12", ["grab", "openhand", "hand1"]),
        ("com.apple.cursor.13", ["pointer", "hand2", "pointing_hand", "hand"]),
        ("com.apple.cursor.17", ["w-resize", "left_side"]),                           // Resize Left
        ("com.apple.cursor.18", ["e-resize", "right_side"]),                          // Resize Right
        ("com.apple.cursor.19", ["col-resize", "split_h", "ew-resize", "sb_h_double_arrow", "h_double_arrow", "size_hor"]),
        ("com.apple.cursor.21", ["n-resize", "top_side"]),                            // Resize Up
        ("com.apple.cursor.22", ["s-resize", "bottom_side"]),                         // Resize Down
        ("com.apple.cursor.23", ["row-resize", "split_v", "ns-resize", "sb_v_double_arrow", "v_double_arrow", "size_ver"]),
        ("com.apple.cursor.24", ["context-menu"]),
        ("com.apple.cursor.26", ["vertical-text"]),
        ("com.apple.cursor.27", ["e-resize", "right_side"]),                          // Resize East
        ("com.apple.cursor.28", ["ew-resize", "sb_h_double_arrow", "h_double_arrow", "size_hor"]),
        ("com.apple.cursor.29", ["ne-resize", "top_right_corner"]),
        ("com.apple.cursor.30", ["nesw-resize", "fd_double_arrow", "size_bdiag"]),
        ("com.apple.cursor.31", ["n-resize", "top_side"]),                            // Resize North
        ("com.apple.cursor.32", ["ns-resize", "sb_v_double_arrow", "v_double_arrow", "size_ver"]),
        ("com.apple.cursor.33", ["nw-resize", "top_left_corner"]),
        ("com.apple.cursor.34", ["nwse-resize", "bd_double_arrow", "size_fdiag"]),
        ("com.apple.cursor.35", ["se-resize", "bottom_right_corner"]),
        ("com.apple.cursor.36", ["s-resize", "bottom_side"]),                         // Resize South
        ("com.apple.cursor.37", ["sw-resize", "bottom_left_corner"]),
        ("com.apple.cursor.38", ["w-resize", "left_side"]),                           // Resize West
        ("com.apple.cursor.40", ["help", "question_arrow", "whats_this", "left_ptr_help", "dnd-ask"]),
        ("com.apple.cursor.41", ["cell", "plus"]),
        ("com.apple.cursor.42", ["zoom-in", "zoom_in"]),
        ("com.apple.cursor.43", ["zoom-out", "zoom_out"]),
    ]

    /// Reads the theme in `folder`: either the theme folder (with `index.theme` and a
    /// `cursors` folder) or a folder of Xcursor files itself. Links that point outside the
    /// folder are ignored, since the theme may come from an archive.
    public static func load(folder: URL) throws -> XcursorTheme {
        let cursorsFolder = folder.appending(path: "cursors", directoryHint: .isDirectory)
        let hasCursorsFolder = (try? cursorsFolder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        let source = hasCursorsFolder ? cursorsFolder : folder
        let root = source.resolvingSymlinksInPath().standardizedFileURL.path + "/"

        var files: [String: URL] = [:]
        let contents = (try? FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
        for url in contents where !url.lastPathComponent.hasPrefix(".") {
            let target = url.resolvingSymlinksInPath().standardizedFileURL
            guard target.path.hasPrefix(root), Xcursor.isXcursorFile(at: target) else { continue }
            files[url.lastPathComponent] = target
        }
        guard !files.isEmpty else { throw XcursorError.noCursorsFound }

        // The `cursors` folder itself may have been chosen: the theme is its parent then.
        let themeFolder = !hasCursorsFolder && folder.lastPathComponent == "cursors"
            ? folder.deletingLastPathComponent() : folder
        let name = themeName(in: themeFolder.appending(path: "index.theme")) ?? themeFolder.lastPathComponent
        return XcursorTheme(name: name, files: files)
    }

    /// Whether `folder` holds an Xcursor theme (directly or in its `cursors` folder).
    public static func isTheme(_ folder: URL) -> Bool {
        let cursorsFolder = folder.appending(path: "cursors", directoryHint: .isDirectory)
        for candidate in [cursorsFolder, folder] {
            let contents = (try? FileManager.default.contentsOfDirectory(at: candidate, includingPropertiesForKeys: nil)) ?? []
            if contents.contains(where: { !$0.lastPathComponent.hasPrefix(".") && Xcursor.isXcursorFile(at: $0) }) {
                return true
            }
        }
        return false
    }

    /// `Name=` in the `[Icon Theme]` section.
    static func themeName(in indexTheme: URL) -> String? {
        guard let text = try? String(contentsOf: indexTheme, encoding: .utf8) else { return nil }
        var inIconTheme = false
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inIconTheme = line == "[Icon Theme]"
            } else if inIconTheme, line.hasPrefix("Name=") {
                let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    public func makeCape(author: String) throws -> (cape: Cape, skipped: [String]) {
        var cursors: [CapeCursor] = []
        var skipped: [String] = []
        // Many names are links to the same file: convert each file once.
        var converted: [URL: CapeCursor?] = [:]
        for (identifier, names) in Self.macNames {
            guard let name = names.first(where: { files[$0] != nil }), let url = files[name] else { continue }
            if converted[url] == nil {
                do {
                    converted[url] = try Xcursor.capeCursor(from: Data(contentsOf: url), identifier: identifier)
                } catch {
                    converted[url] = .some(nil)
                    skipped.append(name)
                }
            }
            guard var cursor = converted[url] ?? nil else { continue }
            cursor.identifier = identifier
            cursors.append(cursor)
        }
        guard !cursors.isEmpty else { throw XcursorError.noCursorsFound }
        let slug = name.lowercased().filter { $0.isLetter || $0.isNumber }
        let cape = Cape(identifier: "local.xcursor.\(slug.isEmpty ? "theme" : slug)",
                        name: name, author: author, version: 1, isHiDPI: true, cursors: cursors)
        return (cape, skipped)
    }
}
