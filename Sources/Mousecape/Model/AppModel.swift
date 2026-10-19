import AppKit
import Observation
import UniformTypeIdentifiers
import CapeKit

/// App-wide state shared by the window and the menu commands: the library, the selection,
/// and the user-facing side of importing, applying and deleting.
@MainActor @Observable
final class AppModel {
    let library = Library()
    let loginAgent = LoginAgent()

    var selection: Cape.ID?
    var errorMessage: String?
    /// An import waiting for "Replace?" confirmation.
    var pendingReplacement: PendingReplacement?
    var capeToDelete: Cape?
    /// An edited cape waiting for "Revert to the original?" confirmation.
    var capeToRevert: Cape?
    /// The cape whose history sheet is open.
    var historyCape: Cape?

    var selectedCape: Cape? { library.capes.first { $0.id == selection } }

    init() {
        loginAgent.repairIfNeeded()
    }

    static let capeType = UTType(filenameExtension: "cape") ?? .propertyList
    static let mightyMouseType = UTType(filenameExtension: "MightyMouse") ?? .propertyList

    // MARK: - Applying

    func apply(_ cape: Cape) {
        perform { try library.apply(cape) }
    }

    func resetToDefault() {
        perform { try library.resetToDefault() }
    }

    /// The applied cape again, or the macOS cursors; used when left-handed mode changes.
    func reapply() {
        perform { try library.reapply() }
    }

    // MARK: - Importing

    /// Imports capes, MightyMouse files and Windows or Linux cursor themes (from the open
    /// panel, Finder or drag and drop).
    func importFiles(_ urls: [URL]) {
        // Loose cursor files dropped together make one cape (one per format).
        let looseWindows = urls.filter { ThemeImport.windowsExtensions.contains($0.pathExtension.lowercased()) }
        let looseXcursors = urls.filter(ThemeImport.isLooseXcursor)
        if !looseWindows.isEmpty {
            importTheme { try convert(ThemeImport.windowsTheme(files: looseWindows)) }
        }
        if !looseXcursors.isEmpty {
            importTheme { try convert(ThemeImport.xcursorTheme(files: looseXcursors)) }
        }
        for url in urls where !looseWindows.contains(url) && !looseXcursors.contains(url) {
            if ThemeImport.handles(url) {
                importTheme { try ThemeImport.withTheme(at: url, convert) }
                continue
            }
            if url.pathExtension.lowercased() == "mightymouse" {
                importMightyMouse(url)
                continue
            }
            do {
                if let existing = try library.existingCape(forFileAt: url),
                   existing.fileURL?.standardizedFileURL != url.standardizedFileURL {
                    pendingReplacement = PendingReplacement(source: .file(url), existing: existing)
                    return      // the confirmation dialog continues with confirmReplacement()
                }
                let cape = try library.importCape(at: url)
                selection = cape.id
            } catch {
                show(error, file: url)
            }
        }
    }

    func confirmReplacement() {
        guard let pending = pendingReplacement else { return }
        pendingReplacement = nil
        perform {
            switch pending.source {
            case .file(let url):
                let cape = try library.importCape(at: url)
                selection = cape.id
                if cape.identifier == library.appliedIdentifier { try library.reapply() }
            case .converted(let cape, let skipped):
                let saved = try library.replace(with: cape)
                selection = saved.id
                reportSkipped(skipped, in: saved)
            }
        }
    }

    /// Adds the converted theme next to the cape it would have replaced.
    func keepBoth() {
        guard let pending = pendingReplacement, case .converted(let cape, let skipped) = pending.source else { return }
        pendingReplacement = nil
        perform { try addConverted(cape, skipped: skipped) }
    }

    func showImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.capeType, Self.mightyMouseType] + ThemeImport.contentTypes
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Choose capes, MightyMouse files, or Windows or Linux cursor themes (a theme folder or an archive of one, .inf, .cur or .ani)")
        panel.prompt = String(localized: "Import")
        if panel.runModal() == .OK { importFiles(panel.urls) }
    }

    /// A cape from a Windows or Xcursor theme, and what was left out.
    private func convert(_ theme: any CursorThemeConvertible) throws -> (cape: Cape, skipped: [String]) {
        let author = theme is XcursorTheme ? String(localized: "Linux cursor theme")
                                           : String(localized: "Windows cursor theme")
        return try theme.makeCape(author: author)
    }

    /// Adds a cape converted from a cursor theme and says which cursors were left out. When
    /// the library already has a cape with its identifier (the same theme imported before),
    /// asks whether to replace it.
    private func importTheme(_ convert: () throws -> (cape: Cape, skipped: [String])) {
        perform {
            let (cape, skipped) = try convert()
            if pendingReplacement == nil,
               let existing = library.capes.first(where: { $0.identifier == cape.identifier }) {
                pendingReplacement = PendingReplacement(source: .converted(cape, skipped: skipped), existing: existing)
                return      // the confirmation dialog continues with confirmReplacement() or keepBoth()
            }
            try addConverted(cape, skipped: skipped)
        }
    }

    /// Adds a converted cape under a free identifier and name.
    private func addConverted(_ converted: Cape, skipped: [String]) throws {
        var cape = converted
        // Two themes of the same name ("kiriko" animated and static) shouldn't look alike.
        let names = Set(library.capes.map(\.name))
        if names.contains(cape.name) {
            let base = cape.name
            var number = 2
            while names.contains("\(base) \(number)") { number += 1 }
            cape.name = "\(base) \(number)"
        }
        let added = try library.add(propertyList: cape.propertyList)
        selection = added.id
        reportSkipped(skipped, in: added)
    }

    private func reportSkipped(_ skipped: [String], in cape: Cape) {
        guard !skipped.isEmpty else { return }
        errorMessage = String(localized: "Imported “\(cape.name)”. Left out, as macOS has no matching cursor or the file couldn't be read: \(skipped.joined(separator: ", ")).")
    }

    private func importMightyMouse(_ url: URL) {
        perform {
            guard let plist = Engine.convertMightyMouse(at: url) else { throw LibraryError.conversionFailed }
            selection = try library.add(propertyList: plist).id
        }
    }

    // MARK: - Editing

    /// The cape open in the editor sheet.
    var editorSession: EditorSession?

    func newCape() {
        editorSession = EditorSession(cape: .untitled(author: NSFullUserName()), originalIdentifier: nil)
    }

    /// Opens the editor, at `cursor` when given (e.g. from a problem), else at the details.
    func edit(_ cape: Cape, cursor: String? = nil) {
        editorSession = EditorSession(cape: cape, originalIdentifier: cape.identifier, cursor: cursor)
    }

    /// Saves the editor's draft; returns false (and shows why) if it could not be saved.
    func save(_ cape: Cape, from session: EditorSession) -> Bool {
        do {
            selection = try library.save(cape, originalIdentifier: session.originalIdentifier).id
            editorSession = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func duplicate(_ cape: Cape) {
        perform { selection = try library.duplicate(cape).id }
    }

    // MARK: - Library

    func captureCurrentCursors() {
        perform { selection = try library.captureCurrentCursors().id }
    }

    func confirmRevert() {
        guard let cape = capeToRevert else { return }
        capeToRevert = nil
        perform { selection = try library.revertToOriginal(cape).id }
    }

    /// Restores a stored version; returns the restored cape, or nil (and shows why).
    func restore(_ version: CapeVersion, of cape: Cape) -> Cape? {
        do {
            let restored = try library.restore(version, of: cape)
            selection = restored.id
            return restored
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func confirmDelete() {
        guard let cape = capeToDelete else { return }
        capeToDelete = nil
        perform {
            try library.delete(cape)
            if selection == cape.id { selection = library.capes.first?.id }
        }
    }

    func revealInFinder(_ cape: Cape) {
        guard let url = cape.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openLibraryFolder() {
        NSWorkspace.shared.open(library.folder)
    }

    // MARK: - Private

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    private func show(_ error: Error, file: URL) {
        errorMessage = "\(file.lastPathComponent): \(error.localizedDescription)"
    }
}

/// An import that would replace a cape in the library: a `.cape` file, or a theme already
/// converted into a cape.
struct PendingReplacement {
    enum Source {
        case file(URL)
        case converted(Cape, skipped: [String])
    }

    let source: Source
    let existing: Cape

    /// A converted theme can also be added next to the existing cape, under a new identifier.
    var canKeepBoth: Bool {
        if case .converted = source { true } else { false }
    }
}

/// One opening of the editor: the cape to start from, and the identifier it is saved under
/// in the library (nil for a new cape).
struct EditorSession: Identifiable {
    let id = UUID()
    let cape: Cape
    let originalIdentifier: String?
    /// The cursor to show first; nil shows the cape details.
    var cursor: String? = nil
}
