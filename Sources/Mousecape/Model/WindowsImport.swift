import Foundation
import UniformTypeIdentifiers
import CapeKit

/// Finds the Windows cursor theme behind what the user dropped or chose: a theme folder, its
/// `install.inf`, a `.zip` of it, or single `.cur`/`.ani` files.
enum WindowsImport {
    static let cursorExtensions = WindowsCursorTheme.fileExtensions          // cur, ani, ico

    static var contentTypes: [UTType] {
        ["cur", "ani", "inf"].compactMap { UTType(filenameExtension: $0) } + [.ico, .zip, .folder]
    }

    /// Whether `url` is something this importer handles (rather than a cape).
    static func handles(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return cursorExtensions.contains(ext) || ext == "inf" || ext == "zip" || isFolder(url)
    }

    /// The theme for a folder, `.inf` or `.zip`. For `.zip` files the archive is unpacked
    /// into a temporary folder first.
    static func theme(at url: URL) throws -> WindowsCursorTheme {
        let ext = url.pathExtension.lowercased()
        if ext == "inf" { return try WindowsCursorTheme.load(folder: url.deletingLastPathComponent()) }
        if ext == "zip" {
            let unpacked = try unzip(url)
            guard let folder = themeFolder(in: unpacked) else { throw WindowsCursorError.noCursorsFound }
            var theme = try WindowsCursorTheme.load(folder: folder)
            // A theme without a scheme name is named after its folder; inside a zip that's
            // often meaningless, so prefer the archive's name.
            if theme.name == folder.lastPathComponent, folder == unpacked {
                theme.name = url.deletingPathExtension().lastPathComponent
            }
            return theme
        }
        if isFolder(url), let folder = themeFolder(in: url) {
            return try WindowsCursorTheme.load(folder: folder)
        }
        throw WindowsCursorError.noCursorsFound
    }

    /// A theme from loose cursor files: each file takes the role its name suggests. Files
    /// whose role has no macOS counterpart (or no recognisable name) become the arrow while
    /// that's free, since whoever drops a single cursor wants to use it.
    static func theme(files: [URL]) throws -> WindowsCursorTheme {
        var roles: [WindowsCursorRole: URL] = [:]
        for url in files {
            var role = WindowsCursorRole.guess(fromFileName: url.lastPathComponent) ?? .arrow
            if role.macIdentifiers.isEmpty && roles[.arrow] == nil { role = .arrow }
            if roles[role] == nil { roles[role] = url }
        }
        guard !roles.isEmpty else { throw WindowsCursorError.noCursorsFound }
        let name = files.count == 1 ? files[0].deletingPathExtension().lastPathComponent
                                    : files[0].deletingLastPathComponent().lastPathComponent
        return WindowsCursorTheme(name: name, files: roles)
    }

    // MARK: - Private

    private static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// The folder with the theme: the one holding an `install.inf`, else the first holding
    /// cursor files; searched a few levels deep, since archives often nest a folder.
    private static func themeFolder(in root: URL) -> URL? {
        var withCursors: URL?
        var queue: [(URL, Int)] = [(root, 0)]
        while !queue.isEmpty {
            let (folder, depth) = queue.removeFirst()
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
            if contents.contains(where: { $0.pathExtension.lowercased() == "inf" }),
               contents.contains(where: { cursorExtensions.contains($0.pathExtension.lowercased()) }) {
                return folder
            }
            if withCursors == nil, contents.contains(where: { cursorExtensions.contains($0.pathExtension.lowercased()) }) {
                withCursors = folder
            }
            if depth < 3 {
                queue += contents.filter { isFolder($0) && $0.lastPathComponent != "__MACOSX" }.map { ($0, depth + 1) }
            }
        }
        return withCursors
    }

    private static func unzip(_ archive: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "Mousecape-Windows-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", archive.path, destination.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw WindowsCursorError.noCursorsFound }
        return destination
    }
}
