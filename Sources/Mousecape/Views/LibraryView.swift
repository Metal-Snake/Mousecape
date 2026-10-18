import SwiftUI
import CapeKit

/// The main window: capes on the left, the selected cape on the right.
struct LibraryView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let cape = model.selectedCape {
                CapeDetailView(cape: cape,
                               isApplied: cape.identifier == model.library.appliedIdentifier,
                               problems: model.library.problems[cape.id] ?? [:],
                               onApply: { model.apply(cape) },
                               onEdit: { model.edit(cape) })
            } else if model.library.capes.isEmpty {
                ContentUnavailableView {
                    Label("No Capes", systemImage: "cursorarrow.rays")
                } description: {
                    Text("Drop .cape files here, or choose File → Import.")
                } actions: {
                    Button("Import…") { model.showImportPanel() }
                    Button("New Cape") { model.newCape() }
                }
            } else {
                ContentUnavailableView("Select a Cape", systemImage: "cursorarrow")
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.showImportPanel()
                } label: {
                    Label("Import", systemImage: "plus")
                }
                .help("Import capes or MightyMouse files")
            }
            ToolbarItem {
                Button {
                    model.resetToDefault()
                } label: {
                    Label("Reset to Default", systemImage: "arrow.uturn.backward")
                }
                .help("Use the macOS cursors again")
                .disabled(model.library.appliedIdentifier == nil)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter { ["cape", "mightymouse"].contains($0.pathExtension.lowercased()) }
            model.importFiles(files)
            return !files.isEmpty
        }
        .sheet(item: $model.editorSession) { session in
            CapeEditorView(session: session) { model.save($0, from: session) }
        }
        .alert("Mousecape", isPresented: errorBinding) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog(replaceTitle, isPresented: replaceBinding) {
            Button("Replace") { model.confirmReplacement() }
            Button("Cancel", role: .cancel) { model.pendingReplacement = nil }
        } message: {
            Text("A cape with the same identifier is already in the library.")
        }
        .confirmationDialog(deleteTitle, isPresented: deleteBinding) {
            Button("Move to Trash", role: .destructive) { model.confirmDelete() }
            Button("Cancel", role: .cancel) { model.capeToDelete = nil }
        } message: {
            if model.capeToDelete?.identifier == model.library.appliedIdentifier {
                Text("The cape is applied; the macOS cursors come back.")
            }
        }
        .onAppear {
            if model.selection == nil {
                model.selection = model.library.appliedCape?.id ?? model.library.capes.first?.id
            }
        }
    }

    private var sidebar: some View {
        List(selection: $model.selection) {
            ForEach(model.library.capes) { cape in
                CapeRow(cape: cape, isApplied: cape.identifier == model.library.appliedIdentifier,
                        problems: model.library.problems[cape.id] ?? [:])
                    .tag(cape.id)
                    .contextMenu { contextMenu(for: cape) }
            }
            if !model.library.duplicates.isEmpty {
                Section("Duplicate identifiers") {
                    ForEach(model.library.duplicates, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: "doc.on.doc")
                            .foregroundStyle(.secondary)
                            .help("Another cape in the library has the same identifier. Remove this file or change its identifier.")
                            .contextMenu {
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            }
                    }
                }
            }
            if !model.library.unreadable.isEmpty {
                Section("Unreadable") {
                    ForEach(model.library.unreadable, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onDeleteCommand {
            model.capeToDelete = model.selectedCape
        }
    }

    @ViewBuilder
    private func contextMenu(for cape: Cape) -> some View {
        Button("Apply") { model.apply(cape) }
            .disabled(cape.identifier == model.library.appliedIdentifier)
        Button("Edit…") { model.edit(cape) }
        Button("Duplicate") { model.duplicate(cape) }
        Divider()
        Button("Show in Finder") { model.revealInFinder(cape) }
        Divider()
        Button("Move to Trash…", role: .destructive) { model.capeToDelete = cape }
    }

    // MARK: - Dialog bindings

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    private var replaceBinding: Binding<Bool> {
        Binding(get: { model.pendingReplacement != nil }, set: { if !$0 { model.pendingReplacement = nil } })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { model.capeToDelete != nil }, set: { if !$0 { model.capeToDelete = nil } })
    }

    private var replaceTitle: String {
        String(localized: "Replace “\(model.pendingReplacement?.existing.name ?? "")”?")
    }

    private var deleteTitle: String {
        String(localized: "Move “\(model.capeToDelete?.name ?? "")” to the Trash?")
    }
}

private struct CapeRow: View {
    let cape: Cape
    let isApplied: Bool
    let problems: [String: [CursorProblem]]

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let arrow = cape.cursors.first {
                    CursorPreview(cursor: arrow, zoom: min(1, 28 / max(arrow.size.width, arrow.size.height)))
                }
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(cape.name)
                    .lineLimit(1)
                if !cape.author.isEmpty {
                    Text(cape.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if !problems.isEmpty {
                ProblemBadge(problems: problems.values.flatMap { $0 })
                    .help(ProblemBadge.summary(cursorCount: problems.count))
            }
            if isApplied {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Applied")
            }
        }
        .padding(.vertical, 2)
    }
}
