import Foundation
import UniformTypeIdentifiers
import CapeKit

/// Finds the cursor theme behind what the user dropped or chose: a Windows theme (folder,
/// `install.inf`, `.cur`/`.ani` files) or an Xcursor theme from Linux (folder, `cursors`
/// folder, single Xcursor files), also inside an archive.
///
/// Archives are unpacked with the system's own tools: `ditto` for `.zip`, `tar` (libarchive)
/// for `.7z`, `.rar` and `.tar` with gzip, bzip2 or xz. libarchive on macOS has no built-in
/// zstd, so `.tar.zst` isn't offered.
enum ThemeImport {
    static let windowsExtensions = WindowsCursorTheme.fileExtensions          // cur, ani, ico
    static let archiveSuffixes = ["zip", "7z", "rar", "tar", "tgz", "tbz", "tbz2", "txz",
                                  "tar.gz", "tar.bz2", "tar.xz"]

    static var contentTypes: [UTType] {
        let byExtension = ["cur", "ani", "inf", "7z", "rar", "tar", "tgz", "tbz", "tbz2", "txz", "xz"]
            .compactMap { UTType(filenameExtension: $0) }
        return byExtension + [.ico, .zip, .gzip, .bz2, .folder]
    }

    /// Whether `url` is something this importer handles (rather than a cape).
    static func handles(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return windowsExtensions.contains(ext) || ext == "inf" || isArchive(url) || isFolder(url)
            || isLooseXcursor(url)
    }

    /// An Xcursor file: Xcursor files have no extension, so look at the contents.
    static func isLooseXcursor(_ url: URL) -> Bool {
        url.pathExtension.isEmpty && !isFolder(url) && Xcursor.isXcursorFile(at: url)
    }

    static func isArchive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return archiveSuffixes.contains { name.hasSuffix(".\($0)") }
    }

    /// Calls `body` with the theme for a folder, `.inf` or archive. An archive is unpacked
    /// into a temporary folder first, which is removed afterwards.
    static func withTheme<T>(at url: URL, _ body: (any CursorThemeConvertible) throws -> T) throws -> T {
        if url.pathExtension.lowercased() == "inf" {
            return try body(WindowsCursorTheme.load(folder: url.deletingLastPathComponent()))
        }
        if isArchive(url) {
            let unpacked = try unpack(url)
            defer { try? FileManager.default.removeItem(at: unpacked) }
            guard let (folder, theme) = findTheme(in: unpacked) else { throw ThemeImportError.noThemeFound }
            return try body(named(theme, in: folder, root: unpacked, rootName: archiveBaseName(url)))
        }
        if isFolder(url), let (folder, theme) = findTheme(in: url) {
            return try body(named(theme, in: folder, root: url, rootName: url.lastPathComponent))
        }
        throw ThemeImportError.noThemeFound
    }

    /// A Windows theme from loose cursor files: each file takes the role its name suggests.
    /// Files whose role has no macOS counterpart (or no recognisable name) become the arrow
    /// while that's free, since whoever drops a single cursor wants to use it.
    static func windowsTheme(files: [URL]) throws -> WindowsCursorTheme {
        var roles: [WindowsCursorRole: URL] = [:]
        for url in files {
            var role = WindowsCursorRole.guess(fromFileName: url.lastPathComponent) ?? .arrow
            if role.macIdentifiers.isEmpty && roles[.arrow] == nil { role = .arrow }
            if roles[role] == nil { roles[role] = url }
        }
        guard !roles.isEmpty else { throw WindowsCursorError.noCursorsFound }
        return WindowsCursorTheme(name: themeName(files), files: roles)
    }

    /// An Xcursor theme from loose Xcursor files, by their names (`left_ptr`, `xterm`, …).
    /// A single file with a name macOS has no counterpart for becomes the arrow.
    static func xcursorTheme(files: [URL]) -> XcursorTheme {
        var byName = Dictionary(files.map { ($0.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
        let known = Set(XcursorTheme.macNames.flatMap(\.names))
        if files.count == 1, !known.contains(files[0].lastPathComponent) {
            byName = ["default": files[0]]
        }
        return XcursorTheme(name: themeName(files), files: byName)
    }

    // MARK: - Private

    private static func themeName(_ files: [URL]) -> String {
        files.count == 1 ? files[0].deletingPathExtension().lastPathComponent
                         : files[0].deletingLastPathComponent().lastPathComponent
    }

    private static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// A theme without a name of its own is named after its folder. When that's a size
    /// folder (`x2`) or `cursors`, the folder above says more; at the top of an archive,
    /// the archive's name does.
    private static func named(_ theme: any CursorThemeConvertible, in folder: URL, root: URL,
                              rootName: String) -> any CursorThemeConvertible {
        guard theme.name == folder.lastPathComponent else { return theme }
        let rootPath = root.standardizedFileURL.path
        var current = folder.standardizedFileURL
        while current.path != rootPath, current.path.hasPrefix(rootPath),
              sizeValue(current.lastPathComponent) != nil || current.lastPathComponent.lowercased() == "cursors" {
            current = current.deletingLastPathComponent()
        }
        var renamed = theme
        renamed.name = current.path == rootPath ? rootName : current.lastPathComponent
        return renamed
    }

    /// The size a folder name stands for: `x2`, `2x`, `@2x`, `32`, `32px`, `150%`.
    static func sizeValue(_ name: String) -> Int? {
        let lower = name.lowercased()
        guard let match = lower.wholeMatch(of: /(?:x|@)?(\d{1,4})(?:x|px|%)?/) else { return nil }
        return Int(match.1)
    }

    /// Windows packs sometimes keep each size in a folder of its own (`x1` … `x5`, `32`,
    /// `48`, …). Of such siblings, the largest: the converter scales down, never up.
    private static func largestSizeVariant(of folder: URL) -> URL {
        guard sizeValue(folder.lastPathComponent) != nil else { return folder }
        let siblings = (try? FileManager.default.contentsOfDirectory(
            at: folder.deletingLastPathComponent(), includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles)) ?? []
        let variants = siblings.filter { sibling in
            guard isFolder(sibling), sizeValue(sibling.lastPathComponent) != nil else { return false }
            let files = (try? FileManager.default.contentsOfDirectory(atPath: sibling.path)) ?? []
            return files.contains { windowsExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
        }
        return variants.max { sizeValue($0.lastPathComponent)! < sizeValue($1.lastPathComponent)! } ?? folder
    }

    private static func archiveBaseName(_ url: URL) -> String {
        let name = url.lastPathComponent
        let suffix = archiveSuffixes.filter { name.lowercased().hasSuffix(".\($0)") }.max { $0.count < $1.count }
        return suffix.map { String(name.dropLast($0.count + 1)) } ?? name
    }

    /// The theme in `root` or a folder below it (archives often nest folders, Windows packs
    /// up to `windows/cursors/<name>/<size>`):
    /// searched breadth first, so the shallowest wins. In one folder, a Windows theme with an
    /// `install.inf` comes first, then an Xcursor theme, then loose Windows cursors.
    private static func findTheme(in root: URL) -> (URL, any CursorThemeConvertible)? {
        var looseWindows: URL?
        var queue: [(URL, Int)] = [(root, 0)]
        while !queue.isEmpty {
            let (folder, depth) = queue.removeFirst()
            let contents = ((try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            let hasWindowsCursors = contents.contains { windowsExtensions.contains($0.pathExtension.lowercased()) }
            if hasWindowsCursors, contents.contains(where: { $0.pathExtension.lowercased() == "inf" }) {
                let variant = largestSizeVariant(of: folder)
                if let theme = try? WindowsCursorTheme.load(folder: variant) { return (variant, theme) }
            }
            if XcursorTheme.isTheme(folder), let theme = try? XcursorTheme.load(folder: folder) {
                return (folder, theme)
            }
            if looseWindows == nil, hasWindowsCursors { looseWindows = folder }
            if depth < 5 {
                queue += contents.filter { isFolder($0) && $0.lastPathComponent != "__MACOSX" }.map { ($0, depth + 1) }
            }
        }
        if let folder = looseWindows.map(largestSizeVariant), let theme = try? WindowsCursorTheme.load(folder: folder) {
            return (folder, theme)
        }
        return nil
    }

    private static func unpack(_ archive: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "Mousecape-Import-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let process = Process()
        if archive.pathExtension.lowercased() == "zip" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archive.path, destination.path]
        } else {
            // bsdtar recognises the format and compression from the contents. Without -P it
            // refuses absolute paths and "..", and won't write through links.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-x", "-f", archive.path, "-C", destination.path]
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw ThemeImportError.cannotUnpack(archive.lastPathComponent)
        }
        return destination
    }
}

enum ThemeImportError: LocalizedError {
    case noThemeFound
    case cannotUnpack(String)

    var errorDescription: String? {
        switch self {
        case .noThemeFound:
            String(localized: "No cursor theme was found: neither Windows cursors (.cur, .ani) nor Linux Xcursor files.")
        case .cannotUnpack(let name):
            String(localized: "“\(name)” could not be unpacked.")
        }
    }
}
