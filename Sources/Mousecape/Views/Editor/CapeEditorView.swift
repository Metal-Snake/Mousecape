import SwiftUI
import CapeKit

/// The cape editor sheet: cape details and the cursor list on the left, the selected part
/// on the right. Works on a draft; nothing touches the library until Save.
struct CapeEditorView: View {
    let session: EditorSession
    /// Saves the draft; returns false if it failed (the sheet then stays open).
    let onSave: (Cape) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Cape
    @State private var selection: Item? = .info
    @State private var confirmDiscard = false

    enum Item: Hashable {
        case info
        case cursor(String)
    }

    init(session: EditorSession, onSave: @escaping (Cape) -> Bool) {
        self.session = session
        self.onSave = onSave
        _draft = State(initialValue: session.cape)
    }

    private var hasChanges: Bool { draft != session.cape || session.originalIdentifier == nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 230)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 860, idealWidth: 920, maxWidth: .infinity, minHeight: 540, idealHeight: 600, maxHeight: .infinity)
        .resizableSheet(minWidth: 860, minHeight: 540, sizeKey: "capeEditor")
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog("Discard your changes to “\(draft.name)”?", isPresented: $confirmDiscard) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Label("Cape Details", systemImage: "info.circle")
                    .tag(Item.info)
                Section("Cursors") {
                    ForEach(draft.cursors) { cursor in
                        CursorRow(cursor: cursor)
                            .tag(Item.cursor(cursor.identifier))
                    }
                }
            }
            .onDeleteCommand(perform: removeSelectedCursor)

            Divider()
            HStack(spacing: 4) {
                Menu {
                    ForEach(draft.missingCursorIdentifiers, id: \.self) { identifier in
                        Button(CursorNames.name(for: identifier)) { addCursor(identifier) }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(draft.missingCursorIdentifiers.isEmpty)
                .help("Add a cursor")

                Button(action: removeSelectedCursor) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selectedCursorIdentifier == nil)
                .help("Remove the selected cursor")
                Spacer()
            }
            .padding(8)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .info, nil:
            CapeInfoForm(cape: $draft)
        case .cursor(let identifier):
            if let binding = cursorBinding(identifier) {
                CursorEditorView(cursor: binding)
                    .id(identifier)
            } else {
                ContentUnavailableView("No Cursor Selected", systemImage: "cursorarrow")
            }
        }
    }

    private var footer: some View {
        HStack {
            let problemCount = draft.problems.count
            if problemCount > 0 {
                Label(ProblemBadge.summary(cursorCount: problemCount), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            Spacer()
            Button("Cancel", role: .cancel) {
                if hasChanges && draft != session.cape { confirmDiscard = true } else { dismiss() }
            }
            .keyboardShortcut(.cancelAction)
            Button("Save") { _ = onSave(draft) }
                .keyboardShortcut("s")
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges)
        }
        .padding(12)
    }

    // MARK: - Cursors

    private var selectedCursorIdentifier: String? {
        if case .cursor(let identifier) = selection { identifier } else { nil }
    }

    private func cursorBinding(_ identifier: String) -> Binding<CapeCursor>? {
        guard draft.cursors.contains(where: { $0.identifier == identifier }) else { return nil }
        // The fallback only shows for the instant a removed cursor is still on screen.
        return Binding {
            draft.cursors.first { $0.identifier == identifier }
                ?? CapeCursor(identifier: identifier, size: CGSize(width: 32, height: 32), representations: [])
        } set: { newValue in
            if let index = draft.cursors.firstIndex(where: { $0.identifier == identifier }) {
                draft.cursors[index] = newValue
            }
        }
    }

    private func addCursor(_ identifier: String) {
        draft.addCursor(identifier: identifier)
        selection = .cursor(identifier)
    }

    private func removeSelectedCursor() {
        guard let identifier = selectedCursorIdentifier,
              let index = draft.cursors.firstIndex(where: { $0.identifier == identifier }) else { return }
        draft.removeCursor(identifier: identifier)
        let next = draft.cursors.indices.contains(index) ? draft.cursors[index] : draft.cursors.last
        selection = next.map { .cursor($0.identifier) } ?? .info
    }
}

private struct CursorRow: View {
    let cursor: CapeCursor

    var body: some View {
        HStack(spacing: 8) {
            CursorPreview(cursor: cursor, zoom: min(1, 22 / max(cursor.size.width, cursor.size.height)))
                .frame(width: 24, height: 24)
            Text(cursor.name)
                .lineLimit(1)
            Spacer()
            if !cursor.problems.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(cursor.problems.map(\.description).joined(separator: "\n"))
            }
        }
    }
}

/// Name, author, identifier and version of the cape.
private struct CapeInfoForm: View {
    @Binding var cape: Cape

    var body: some View {
        Form {
            Section("Cape") {
                TextField("Name", text: $cape.name)
                TextField("Author", text: $cape.author)
                TextField("Version", value: $cape.version, format: .number)
                Toggle("Includes HiDPI images", isOn: $cape.isHiDPI)
            }
            Section {
                LabeledContent("Identifier") {
                    TextField("Identifier", text: $cape.identifier)
                        .labelsHidden()
                        .font(.body.monospaced())
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                Text("Unique reverse-DNS name, e.g. com.yourname.capename. It is the file name in the library; importing a cape with the same identifier replaces this one.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                LabeledContent("Cursors", value: "\(cape.cursors.count)")
                if cape.cursors.isEmpty {
                    Text("Add cursors with the + button below the list.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
