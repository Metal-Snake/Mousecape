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
    /// The import the "Replace?" dialog asks about.
    private(set) var pendingReplacement: PendingReplacement?
    /// A dropped or opened theme that comes in several versions: the library window asks
    /// which one to import. Closing the question shows the next one, if more are waiting.
    var themeChoice: ThemeChoice? {
        didSet { if themeChoice == nil { showNextChoice() } }
    }
    @ObservationIgnored private var queuedChoices: [ThemeChoice] = []
    /// Further imports that would replace a cape. They are asked about one after the other.
    private var queuedReplacements: [PendingReplacement] = []
    private var nextReplacementScheduled = false
    var capeToDelete: Cape?
    /// An edited cape waiting for "Revert to the original?" confirmation.
    var capeToRevert: Cape?
    /// The cape whose history sheet is open.
    var historyCape: Cape?

    var selectedCape: Cape? { library.capes.first { $0.id == selection } }

    init() {
        loginAgent.repairIfNeeded()
        gallery.installedThemeIDs = { [library] in library.installedGalleryThemes }
    }

    static let capeType = UTType(filenameExtension: "cape") ?? .propertyList
    static let mightyMouseType = UTType(filenameExtension: "MightyMouse") ?? .propertyList
    static let maCursorType = UTType(filenameExtension: MaCursorTheme.fileExtension) ?? .propertyList

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

    private var appliedAtLaunch = false

    /// Applies the cape marked as applied again, once per launch, as the original did. The
    /// cursors on screen can differ from that mark (another tool, or macOS, reset them), and
    /// the agent may be off. A cape that is only partly applied isn't reported here: the
    /// cape view already lists its problems, and an alert at every launch would not help.
    func applyAtLaunch() {
        guard !appliedAtLaunch else { return }
        appliedAtLaunch = true
        guard let cape = library.appliedCape else { return }
        do {
            try library.apply(cape)
        } catch LibraryError.partiallyApplied {
        } catch {
            errorMessage = error.localizedDescription
        }
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
                importVersions(of: url)
                continue
            }
            if url.pathExtension.lowercased() == "mightymouse" {
                importMightyMouse(url)
                continue
            }
            if url.pathExtension.lowercased() == MaCursorTheme.fileExtension {
                importTheme { try MaCursorTheme(contentsOf: url).makeCape(author: String(localized: "MaCursor theme")) }
                continue
            }
            do {
                if let existing = try library.existingCape(forFileAt: url),
                   existing.fileURL?.standardizedFileURL != url.standardizedFileURL {
                    askToReplace(PendingReplacement(source: .file(url), existing: existing))
                    continue    // the dialog continues with confirmReplacement()
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
        defer { showNextReplacement() }
        perform {
            switch pending.source {
            case .file(let url):
                let cape = try library.importCape(at: url)
                selection = cape.id
                if cape.identifier == library.appliedIdentifier { try library.reapply() }
            case .converted(let versions):
                try add(versions, replacing: true)
            }
        }
    }

    /// Adds the converted themes next to the capes they would have replaced.
    func keepBoth() {
        guard let pending = pendingReplacement, case .converted(let versions) = pending.source else { return }
        pendingReplacement = nil
        defer { showNextReplacement() }
        perform { try add(versions, replacing: false) }
    }

    /// Leaves the cape the dialog asks about as it is (Cancel, or the dialog closed).
    func cancelReplacement() {
        pendingReplacement = nil
        showNextReplacement()
    }

    private func askToReplace(_ replacement: PendingReplacement) {
        if pendingReplacement == nil && !nextReplacementScheduled {
            pendingReplacement = replacement
        } else {
            queuedReplacements.append(replacement)
        }
    }

    /// Asks about the next queued import. The dialog has to close before it can open again,
    /// so the next question follows a moment later. Calling this more than once for the same
    /// closing (the button, then the dialog's own dismissal) asks only once.
    private func showNextReplacement() {
        guard pendingReplacement == nil, !nextReplacementScheduled, !queuedReplacements.isEmpty else { return }
        nextReplacementScheduled = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            nextReplacementScheduled = false
            pendingReplacement = queuedReplacements.removeFirst()
        }
    }

    func showImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.capeType, Self.mightyMouseType, Self.maCursorType] + ThemeImport.contentTypes
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Choose capes, MightyMouse files, MaCursor themes, or Windows or Linux cursor themes (a theme folder or an archive of one, .inf, .cur or .ani)")
        panel.prompt = String(localized: "Import")
        if panel.runModal() == .OK { importFiles(panel.urls) }
    }

    /// A cape from a Windows or Xcursor theme, and what was left out.
    private func convert(_ theme: any CursorThemeConvertible) throws -> (cape: Cape, skipped: [String]) {
        let author = theme is XcursorTheme ? String(localized: "Linux cursor theme")
                                           : String(localized: "Windows cursor theme")
        return try theme.makeCape(author: author)
    }

    /// Imports a theme folder or archive. With one theme in it, right away; with several
    /// versions (Regular, Large, …), the library window asks which.
    private func importVersions(of url: URL) {
        perform {
            // Converted while the archive is unpacked: the themes read their files lazily.
            let options = try ThemeImport.withThemes(at: url) { found in
                try Self.convertEach(found.map { item in { [self] in
                    let (cape, skipped) = try convert(item.theme)
                    return ThemeOption(cape: cape, skipped: skipped, kind: ThemeOption.Kind(item.theme),
                                       fileName: url.lastPathComponent, variant: item.variant)
                } })
            }
            if options.count == 1 {
                importConverted(options.map { ($0.cape, $0.skipped) })
            } else {
                offer(ThemeChoice(title: url.lastPathComponent, options: options))
            }
        }
    }

    /// The versions that convert; an error only when none does.
    private nonisolated static func convertEach(_ conversions: [() throws -> ThemeOption]) throws -> [ThemeOption] {
        var options: [ThemeOption] = []
        var firstError: Error?
        for conversion in conversions {
            do { options.append(try conversion()) } catch { firstError = firstError ?? error }
        }
        if options.isEmpty { throw firstError ?? ThemeImportError.noThemeFound }
        return options
    }

    /// Imports the versions chosen in the library window, each as a cape of its own.
    func importVersions(_ options: [ThemeOption]) {
        importConverted(Self.distinguished(options))
    }

    /// The chosen versions with names and identifiers that tell them apart.
    private static func distinguished(_ options: [ThemeOption]) -> [(cape: Cape, skipped: [String])] {
        let capes = ThemeVersions.distinguished(options.map { option in
            ThemeVersions.Version(cape: option.cape, variant: option.variant, kind: option.kind.shortTitle)
        })
        return zip(capes, options).map { ($0, $1.skipped) }
    }

    private func offer(_ choice: ThemeChoice) {
        if themeChoice == nil { themeChoice = choice } else { queuedChoices.append(choice) }
    }

    /// A sheet has to close before the next can open, so the next question follows a
    /// moment later.
    private func showNextChoice() {
        guard !queuedChoices.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if themeChoice == nil, !queuedChoices.isEmpty { themeChoice = queuedChoices.removeFirst() }
        }
    }

    /// Adds a cape converted from a cursor theme and says which cursors were left out.
    private func importTheme(_ convert: () throws -> (cape: Cape, skipped: [String])) {
        perform { importConverted([try convert()]) }
    }

    /// Adds capes converted from cursor themes. When the library already has some of them
    /// (the same version from the gallery, or a cape with the same identifier: the same
    /// theme imported before), asks once whether to replace them.
    private func importConverted(_ converted: [(cape: Cape, skipped: [String])]) {
        var taken = Set<String>()       // two new capes may not replace the same one
        let versions = converted.map { item in
            let existing = installedCape(like: item.cape, except: taken)
            if let existing { taken.insert(existing.identifier) }
            return ConvertedVersion(cape: item.cape, skipped: item.skipped, existing: existing)
        }
        let replaced = versions.compactMap(\.existing)
        if let first = replaced.first {
            askToReplace(PendingReplacement(source: .converted(versions), existing: first, count: replaced.count))
            return      // the dialog continues with confirmReplacement() or keepBoth()
        }
        perform { try add(versions, replacing: false) }
    }

    /// The cape in the library a converted cape would replace: the one installed from the
    /// same version of the same gallery theme, or else the one with its identifier.
    private func installedCape(like cape: Cape, except taken: Set<String>) -> Cape? {
        let candidates = library.capes.filter { !taken.contains($0.identifier) }
        if let source = cape.source, let same = candidates.first(where: { installed in
            installed.source.map { $0.site == source.site && $0.themeID == source.themeID
                && $0.fileName == source.fileName && $0.variant == source.variant } ?? false
        }) {
            return same
        }
        return candidates.first { $0.identifier == cape.identifier }
    }

    /// Writes converted capes: over the capes they replace when `replacing`, else next to
    /// them under a free identifier and name. Selects the first and says what was left out.
    private func add(_ versions: [ConvertedVersion], replacing: Bool) throws {
        var saved: [(cape: Cape, skipped: [String])] = []
        for version in versions {
            if replacing, let existing = version.existing {
                var cape = version.cape
                // The same version from the gallery keeps its place and name in the library.
                cape.identifier = existing.identifier
                if cape.source != nil, existing.source != nil { cape.name = existing.name }
                saved.append((try library.replace(with: cape), version.skipped))
            } else {
                saved.append((try addConverted(version.cape), version.skipped))
            }
        }
        if let first = saved.first { selection = first.cape.id }
        reportSkipped(saved)
    }

    /// Adds a converted cape under a free identifier and name.
    private func addConverted(_ converted: Cape) throws -> Cape {
        var cape = converted
        // Two themes of the same name ("kiriko" animated and static) shouldn't look alike.
        let names = Set(library.capes.map(\.name))
        if names.contains(cape.name) {
            let base = cape.name
            var number = 2
            while names.contains("\(base) \(number)") { number += 1 }
            cape.name = "\(base) \(number)"
        }
        return try library.add(propertyList: cape.propertyList)
    }

    private func reportSkipped(_ skipped: [String], in cape: Cape) {
        reportSkipped([(cape, skipped)])
    }

    /// Says which cursors the imported capes left out, for all of them in one message.
    private func reportSkipped(_ imported: [(cape: Cape, skipped: [String])]) {
        let incomplete = imported.filter { !$0.skipped.isEmpty }
        guard !incomplete.isEmpty else { return }
        if imported.count == 1, let only = incomplete.first {
            errorMessage = String(localized: "Imported “\(only.cape.name)”. Left out, as macOS has no matching cursor or the file couldn't be read: \(only.skipped.joined(separator: ", ")).")
            return
        }
        if incomplete.count == imported.count, Set(incomplete.map(\.skipped)).count == 1 {
            // Versions of one theme usually leave out the same cursors: name them once.
            errorMessage = String(localized: "Imported \(imported.count) capes. Each leaves out, as macOS has no matching cursor or the file couldn't be read: \(incomplete[0].skipped.joined(separator: ", ")).")
            return
        }
        let lists = incomplete.map { "\($0.cape.name): \($0.skipped.joined(separator: ", "))" }.joined(separator: "\n")
        errorMessage = String(localized: "Imported \(imported.count) capes. Left out, as macOS has no matching cursor or the file couldn't be read:\n\(lists)")
    }

    // MARK: - Gallery

    let gallery = CursorGallery()

    /// Downloads files of a gallery theme and converts each, with every version an archive
    /// holds. A single version is installed right away (nil comes back); several come back
    /// as a choice, so that the gallery can ask which. The author is the uploader's name on
    /// pling.com, unless the theme names its own.
    func prepareInstall(_ files: [PlingTheme.File], of theme: PlingTheme) async -> ThemeChoice? {
        do {
            let downloads = try await gallery.download(files, of: theme)
            defer {
                for download in downloads { try? FileManager.default.removeItem(at: download.file.deletingLastPathComponent()) }
            }
            var options: [ThemeOption] = []
            var firstError: Error?
            for download in downloads {
                let path = download.file, author = theme.author
                do {
                    // Unpacking and converting can take a moment; not on the main thread.
                    let versions = try await Task.detached { try Self.convertDownload(at: path, author: author) }.value
                    options += versions.map { $0.from(theme: theme, file: download.info) }
                } catch {
                    firstError = firstError ?? error        // another file may still work
                }
            }
            if options.isEmpty { throw firstError ?? ThemeImportError.noThemeFound }
            if options.count == 1 {
                install(options)
                return nil
            }
            return ThemeChoice(title: theme.name, options: options)
        } catch {
            errorMessage = String(localized: "“\(theme.name)” could not be installed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Imports versions of a gallery theme like a dropped file, each as a cape of its own: a
    /// question about replacing capes holds the converted capes, not the downloaded file.
    func install(_ options: [ThemeOption]) {
        importConverted(Self.distinguished(options))
    }

    /// A downloaded file as capes: a cape as it is, a MaCursor theme, or every theme in an
    /// archive converted.
    nonisolated static func convertDownload(at url: URL, author: String) throws -> [ThemeOption] {
        let name = url.lastPathComponent
        switch url.pathExtension.lowercased() {
        case "cape":
            var cape = try Cape(contentsOf: url)
            cape.fileURL = nil
            return [ThemeOption(cape: cape, skipped: [], kind: .cape, fileName: name, variant: nil)]
        case MaCursorTheme.fileExtension:
            let (cape, skipped) = try MaCursorTheme(contentsOf: url).makeCape(author: author)
            return [ThemeOption(cape: cape, skipped: skipped, kind: .maCursor, fileName: name, variant: nil)]
        default:
            // Converted while the archive is unpacked: the themes read their files lazily.
            return try ThemeImport.withThemes(at: url) { found in
                try convertEach(found.map { item in {
                    let (cape, skipped) = try item.theme.makeCape(author: author)
                    return ThemeOption(cape: cape, skipped: skipped, kind: ThemeOption.Kind(item.theme),
                                       fileName: name, variant: item.variant)
                } })
            }
        }
    }

    // MARK: - Gallery updates

    /// The newer file of an installed theme, when pling.com has one; nil when the theme
    /// isn't installed, is up to date, or it can't be told.
    func update(for theme: PlingTheme) -> PlingTheme.File? {
        guard let source = library.cape(installedFromGalleryTheme: theme.id)?.source else { return nil }
        return theme.updatedFile(installedName: source.fileName, installedMD5: source.md5,
                                 among: CursorGallery.installableFiles(of: theme))
    }

    /// Downloads and converts the newer file, without saving anything: the installed cape,
    /// the cape the update would make of it, and what the update leaves out.
    func prepareUpdate(_ file: PlingTheme.File, of theme: PlingTheme) async throws -> PreparedUpdate {
        guard let installed = library.cape(installedFromGalleryTheme: theme.id) else { throw LibraryError.notInLibrary }
        let downloaded = try await gallery.download(file, of: theme)
        defer { try? FileManager.default.removeItem(at: downloaded.file.deletingLastPathComponent()) }
        let path = downloaded.file, author = theme.author
        // Unpacking and converting can take a moment; not on the main thread.
        let versions = try await Task.detached { try Self.convertDownload(at: path, author: author) }.value
        // The same version as before; a cape from a file with one theme takes that one, as
        // does one installed before Mousecape knew versions.
        let wanted = installed.source?.variant
        guard let version = versions.first(where: { $0.variant == wanted })
                ?? (versions.count == 1 || wanted == nil ? versions.first : nil) else {
            throw GalleryError.versionGone(wanted ?? "")
        }
        let skipped = version.skipped
        var updated = version.cape
        // The update replaces the cursors, not the cape's place and name in the library.
        updated.identifier = installed.identifier
        updated.name = installed.name
        updated.fileURL = installed.fileURL
        updated.otherKeys = installed.otherKeys
        updated.source = CapeSource(theme: theme, file: downloaded.info, variant: version.variant)
        return PreparedUpdate(themeID: theme.id, installed: installed, updated: updated, skipped: skipped)
    }

    /// Saves the update over the installed cape. The cape's current state stays in its
    /// history, so History → Restore takes the update back; an applied cape is applied
    /// again.
    func applyUpdate(_ update: PreparedUpdate) {
        perform {
            let saved = try library.save(update.updated, originalIdentifier: update.installed.identifier)
            selection = saved.id
            reportSkipped(update.skipped, in: saved)
        }
    }

    /// The update changes nothing in the cape: remember the new file, so it no longer
    /// shows as an update.
    func markUpToDate(_ update: PreparedUpdate) {
        guard let source = update.updated.source else { return }
        perform { try library.updateSource(of: update.installed, to: source) }
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
        trashedForRedo.removeAll()      // a new action: Redo can't go to the old ones
        moveToTrash(cape)
    }

    private func moveToTrash(_ cape: Cape) {
        perform {
            trashedForUndo.append(try library.delete(cape))
            if selection == cape.id { selection = library.capes.first?.id }
        }
    }

    // MARK: - Undo

    /// Capes moved to the Trash, the last one last, for Undo.
    private var trashedForUndo: [TrashedCape] = []
    /// Capes Undo put back (by identifier), for Redo.
    private var trashedForRedo: [String] = []

    /// While the editor is open, Undo and Redo work on its draft; otherwise on the library
    /// (moving capes to the Trash).
    var canUndo: Bool { editorSession.map(\.canUndo) ?? !trashedForUndo.isEmpty }
    var canRedo: Bool { editorSession.map(\.canRedo) ?? !trashedForRedo.isEmpty }

    var undoTitle: String {
        let title = editorSession.map(\.undoTitle) ?? (trashedForUndo.isEmpty ? nil : String(localized: "Move to Trash"))
        return title.map { String(localized: "Undo \($0)") } ?? String(localized: "Undo")
    }

    var redoTitle: String {
        let title = editorSession.map(\.redoTitle) ?? (trashedForRedo.isEmpty ? nil : String(localized: "Move to Trash"))
        return title.map { String(localized: "Redo \($0)") } ?? String(localized: "Redo")
    }

    func undo() {
        if let editorSession { editorSession.undo(); return }
        guard let trashed = trashedForUndo.popLast() else { return }
        perform {
            let cape = try library.putBack(trashed)
            selection = cape.id
            trashedForRedo.append(cape.identifier)
            if trashed.wasApplied { try library.apply(cape) }
        }
    }

    func redo() {
        if let editorSession { editorSession.redo(); return }
        guard let identifier = trashedForRedo.popLast(),
              let cape = library.capes.first(where: { $0.identifier == identifier }) else { return }
        moveToTrash(cape)
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
        /// One or more versions of a theme, some of which replace capes.
        case converted([ConvertedVersion])
    }

    let source: Source
    /// The (first) cape it would replace.
    let existing: Cape
    /// How many capes it would replace.
    var count = 1

    /// A converted theme can also be added next to the existing cape, under a new identifier.
    var canKeepBoth: Bool {
        if case .converted = source { true } else { false }
    }
}

/// A cape converted from a theme, waiting to be added, and the cape it would replace.
struct ConvertedVersion {
    let cape: Cape
    let skipped: [String]
    let existing: Cape?
}

/// An update from the gallery, downloaded and converted but not saved yet.
struct PreparedUpdate: Identifiable {
    var id: Int { themeID }
    let themeID: Int
    let installed: Cape
    let updated: Cape
    let skipped: [String]

    var diff: CapeDiff { CapeDiff(from: installed, to: updated) }
}

/// One version of a theme, converted but not imported yet: one file of a theme, or one
/// theme of several in an archive.
struct ThemeOption: Identifiable {
    enum Kind {
        case linux, windows, cape, maCursor

        init(_ theme: any CursorThemeConvertible) {
            self = theme is XcursorTheme ? .linux : .windows
        }

        var title: String {
            switch self {
            case .linux: String(localized: "Linux theme")
            case .windows: String(localized: "Windows theme")
            case .cape: String(localized: "Cape")
            case .maCursor: String(localized: "MaCursor theme")
            }
        }

        /// The kind in a cape's name, when versions of different kinds are installed.
        var shortTitle: String {
            switch self {
            case .linux: String(localized: "Linux")
            case .windows: String(localized: "Windows")
            case .cape: String(localized: "Cape")
            case .maCursor: String(localized: "MaCursor")
            }
        }
    }

    let id = UUID()
    var cape: Cape
    let skipped: [String]
    let kind: Kind
    /// The file (or folder) it comes from.
    let fileName: String
    /// Its folder in the archive, when it comes from one.
    let variant: String?
    let summary: CapeSummary

    init(cape: Cape, skipped: [String], kind: Kind, fileName: String, variant: String?) {
        self.cape = cape
        self.skipped = skipped
        self.kind = kind
        self.fileName = fileName
        self.variant = variant
        summary = CapeSummary(cape)
    }

    /// The same version with its source on pling.com, which travels with the cape.
    func from(theme: PlingTheme, file: PlingTheme.File) -> ThemeOption {
        var option = self
        option.cape.source = CapeSource(theme: theme, file: file, variant: variant)
        return option
    }
}

/// The versions of a theme to choose from, the suggested one first (see
/// `CapeSummary.suggested`), the others in the order of their files.
struct ThemeChoice: Identifiable {
    let id = UUID()
    let title: String
    let options: [ThemeOption]

    init(title: String, options: [ThemeOption]) {
        self.title = title
        var sorted = options
        if let suggested = CapeSummary.suggested(among: options.map(\.summary)) {
            sorted.insert(sorted.remove(at: suggested), at: 0)
        }
        self.options = sorted
    }

    /// The suggested version (the first), when there is any.
    var suggested: Int? { options.isEmpty ? nil : 0 }
}
