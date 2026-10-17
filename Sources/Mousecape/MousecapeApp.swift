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
        }
        .defaultSize(width: 1000, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Cape") { model.newCape() }
                    .keyboardShortcut("n")
                Button("Import…") { model.showImportPanel() }
                    .keyboardShortcut("o")
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

        Settings {
            SettingsView(model: model)
        }
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
        model?.library.reload()
        model?.loginAgent.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
