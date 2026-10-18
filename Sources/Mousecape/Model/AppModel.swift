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
        loginAgent.renewRegistrationIfNeeded()
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

    // MARK: - Importing

    /// Imports `.cape` and `.MightyMouse` files (from the open panel, Finder or drag and drop).
    func importFiles(_ urls: [URL]) {
        for url in urls {
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
            if cape.identifier == library.appliedIdentifier { library.reapply() }
        }
    }

    func showImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.capeType, Self.mightyMouseType]
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Choose capes or MightyMouse files to add to the library")
        panel.prompt = String(localized: "Import")
        if panel.runModal() == .OK { importFiles(panel.urls) }
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
