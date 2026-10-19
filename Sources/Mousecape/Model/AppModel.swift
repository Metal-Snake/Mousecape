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
    /// An import waiting for "Replace?" confirmation: the file, and the cape it replaces.
    var pendingReplacement: (url: URL, existing: Cape)?
    var capeToDelete: Cape?

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
                    pendingReplacement = (url, existing)
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
        guard let (url, _) = pendingReplacement else { return }
        pendingReplacement = nil
        perform {
            let cape = try library.importCape(at: url)
            selection = cape.id
            if cape.identifier == library.appliedIdentifier { try library.reapply() }
        }
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

    /// Adds a cape converted from a cursor theme and says which cursors were left out.
    private func importTheme(_ convert: () throws -> (cape: Cape, skipped: [String])) {
        perform {
            var (cape, skipped) = try convert()
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
            if !skipped.isEmpty {
                errorMessage = String(localized: "Imported “\(added.name)”. Left out, as macOS has no matching cursor or the file couldn't be read: \(skipped.joined(separator: ", ")).")
            }
        }
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

    func edit(_ cape: Cape) {
        editorSession = EditorSession(cape: cape, originalIdentifier: cape.identifier)
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

/// One opening of the editor: the cape to start from, and the identifier it is saved under
/// in the library (nil for a new cape).
struct EditorSession: Identifiable {
    let id = UUID()
    let cape: Cape
    let originalIdentifier: String?
}
