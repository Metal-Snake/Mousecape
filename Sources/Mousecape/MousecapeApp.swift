import SwiftUI

@main
struct MousecapeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Mousecape", id: "library") {
            LibraryView(model: model)
                .frame(minWidth: 900, minHeight: 620)   // room for the editor sheet
                .onAppear { appDelegate.model = model }
                .task { model.applyAtLaunch() }     // once the window appears
                .focusedSceneValue(\.isLibraryWindow, true)
        }
        .defaultSize(width: 1000, height: 680)
        // Opened files go to AppDelegate.application(_:open:). Left to SwiftUI, the
        // open event closes this window and creates a new one (seen on macOS 27).
        .handlesExternalEvents(matching: [])
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Mousecape") { Self.showAboutPanel() }
            }
            UndoCommands(model: model)
            FindCommands()
            CommandGroup(replacing: .newItem) {
                Button("New Cape") { model.newCape() }
                    .keyboardShortcut("n")
                Button("Import…") { model.showImportPanel() }
                    .keyboardShortcut("o")
                OpenGalleryButton()
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("Cape") {
                Button("Apply") {
                    if let cape = model.selectedCape { model.apply(cape) }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.selectedCape == nil)
                Button("Reset to Default Cursors") { model.resetToDefault() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("Edit…") {
                    if let cape = model.selectedCape { model.edit(cape) }
                }
                .keyboardShortcut("e")
                .disabled(model.selectedCape == nil)
                Button("Duplicate") {
                    if let cape = model.selectedCape { model.duplicate(cape) }
                }
                .keyboardShortcut("d")
                .disabled(model.selectedCape == nil)
                Button("History…") { model.historyCape = model.selectedCape }
                    .keyboardShortcut("y")
                    .disabled(model.selectedCape == nil)
                Button("Revert to Original…") { model.capeToRevert = model.selectedCape }
                    .disabled(!(model.selectedCape.map { model.library.editedIdentifiers.contains($0.identifier) } ?? false))
                Divider()
                Button("Show in Finder") {
                    if let cape = model.selectedCape { model.revealInFinder(cape) }
                }
                .disabled(model.selectedCape == nil)
                Button("Open Library Folder") { model.openLibraryFolder() }
                Divider()
                Button("Capture Current Cursors") { model.captureCurrentCursors() }
                Divider()
                Button("Move to Trash…") { model.capeToDelete = model.selectedCape }
                    .keyboardShortcut(.delete)
                    .disabled(model.selectedCape == nil)
            }
        }

        Window("Cursor Themes Online", id: "gallery") {
            GalleryView(model: model)
        }
        .defaultSize(width: 980, height: 680)

        Settings {
            SettingsView(model: model)
        }
    }

    /// The standard About window. The short version already carries the build ("3.1.0
    /// (404)", so that Finder's Get Info shows it); left alone, the panel would add the
    /// build a second time.
    @MainActor static func showAboutPanel() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        NSApp.orderFrontStandardAboutPanel(options: [.applicationVersion: version, .version: ""])
        NSApp.activate()
    }
}

/// Opens `.cape` files double-clicked in Finder, and keeps the library current when the
/// app comes back to the front.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var model: AppModel? {
        didSet {
            if let model, !pendingFiles.isEmpty {
                model.importFiles(pendingFiles)
                pendingFiles = []
            }
        }
    }
    @MainActor private var pendingFiles: [URL] = []

    @MainActor func application(_ application: NSApplication, open urls: [URL]) {
        if let model { model.importFiles(urls) } else { pendingFiles += urls }
    }

    @MainActor func applicationDidBecomeActive(_ notification: Notification) {
        model?.library.reloadIfChanged()
        model?.loginAgent.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Undo and Redo of the app's own in the library window: the editor's draft, or moving
/// capes to the Trash. The editor's history covers typing in its fields too. In other
/// windows (the gallery's search field) the menu items do what they usually do.
struct UndoCommands: Commands {
    let model: AppModel
    @FocusedValue(\.isLibraryWindow) private var isLibraryWindow

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            if isLibraryWindow == true {
                Button(model.undoTitle) { model.undo() }
                    .keyboardShortcut("z")
                    .disabled(!model.canUndo)
                Button(model.redoTitle) { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.canRedo)
            } else {
                Button("Undo") { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
                    .keyboardShortcut("z")
                Button("Redo") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
    }
}

/// Edit → Find (⌘F): the search field of the window in front, where it has one.
struct FindCommands: Commands {
    @FocusedValue(\.focusSearch) private var focusSearch

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find…") { focusSearch?() }
                .keyboardShortcut("f")
                .disabled(focusSearch == nil)
        }
    }
}

extension FocusedValues {
    /// Set by the library window (and so its sheets), for `UndoCommands`.
    @Entry var isLibraryWindow: Bool?
    /// Puts the focus in the window's search field (the gallery), for `FindCommands`.
    @Entry var focusSearch: (() -> Void)?
}

/// Opens the gallery of cursor themes on pling.com.
struct OpenGalleryButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Browse Cursor Themes Online…") { openWindow(id: "gallery") }
    }
}
