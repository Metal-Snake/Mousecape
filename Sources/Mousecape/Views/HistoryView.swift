import SwiftUI
import CapeKit

/// A cape's stored states (original, saved states, current) and what changed between two
/// of them; any stored state can be restored.
struct HistoryView: View {
    let model: AppModel
    @State var cape: Cape

    @Environment(\.dismiss) private var dismiss
    @State private var versions: [CapeVersion] = []
    @State private var selected: Entry = .current
    @State private var comparedWith: Entry = .current
    @State private var confirmingRemoval = false

    /// A stored version, or the cape as it is now.
    enum Entry: Hashable {
        case current
        case version(CapeVersion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("History — \(cape.name)")
                    .font(.title2.weight(.semibold))
                Text("Mousecape keeps how the cape came into the library and up to \(CapeHistory.savedLimit) states that saves replaced. Restoring keeps the current state in the history too.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 16) {
                list
                    .frame(width: 230)
                comparison
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            footer
        }
        .padding(20)
        .frame(minWidth: 760, idealWidth: 820, maxWidth: .infinity, minHeight: 480, idealHeight: 560, maxHeight: .infinity)
        .resizableSheet(minWidth: 760, minHeight: 480, sizeKey: "history")
        .onAppear(perform: reloadVersions)
        .confirmationDialog("Remove the saved states of “\(cape.name)”?", isPresented: $confirmingRemoval) {
            Button("Move to Trash", role: .destructive) {
                model.library.removeSavedVersions(of: cape)
                reloadVersions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The original and the current state stay.")
        }
    }

    // MARK: - Parts

    private var entries: [Entry] {
        [.current] + versions.reversed().map(Entry.version)
    }

    private var list: some View {
        List(entries, id: \.self, selection: Binding(get: { selected }, set: { select($0 ?? .current) })) { entry in
            VStack(alignment: .leading, spacing: 2) {
                Text(title(of: entry))
                Text(subtitle(of: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .listStyle(.bordered(alternatesRowBackgrounds: false))
    }

    @ViewBuilder
    private var comparison: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Compare with")
                Picker("Compare with", selection: $comparedWith) {
                    ForEach(entries.filter { $0 != selected }, id: \.self) { entry in
                        Text(title(of: entry)).tag(entry)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            if let older = load(earlier), let newer = load(later) {
                let diff = CapeDiff(from: older, to: newer)
                Text("Changes from \(title(of: earlier)) to \(title(of: later))")
                    .font(.headline)
                if diff.isEmpty {
                    Text("No differences.")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    DiffList(diff: diff)
                }
            } else {
                Text("This version can't be read.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Remove Saved States…") { confirmingRemoval = true }
                .disabled(!versions.contains { $0.kind == .saved })
            Spacer()
            Button("Restore This Version") { restore() }
                .disabled(selected == .current)
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Entries

    /// Of the two compared entries, the older and the newer one.
    private var earlier: Entry { order(selected) <= order(comparedWith) ? selected : comparedWith }
    private var later: Entry { earlier == selected ? comparedWith : selected }

    private func order(_ entry: Entry) -> Int {
        switch entry {
        case .current: Int.max
        case .version(let version): versions.firstIndex(of: version) ?? 0
        }
    }

    private func title(of entry: Entry) -> String {
        switch entry {
        case .current: String(localized: "Current")
        case .version(let version) where version.kind == .original: String(localized: "Original")
        case .version(let version):
            String(localized: "Saved \(version.date.formatted(date: .abbreviated, time: .standard))")
        }
    }

    private func subtitle(of entry: Entry) -> String {
        switch entry {
        case .current: String(localized: "In the library")
        case .version(let version) where version.kind == .original:
            String(localized: "As it came in · \(version.date.formatted(date: .abbreviated, time: .standard))")
        case .version: String(localized: "Replaced by a later save")
        }
    }

    private func load(_ entry: Entry) -> Cape? {
        switch entry {
        case .current: cape
        case .version(let version): try? Cape(contentsOf: version.url)
        }
    }

    // MARK: - Actions

    private func select(_ entry: Entry) {
        selected = entry
        if comparedWith == entry {
            comparedWith = entry == .current ? (versions.first.map(Entry.version) ?? .current) : .current
        }
    }

    private func reloadVersions() {
        versions = model.library.versions(of: cape)
        if case .version(let version) = selected, !versions.contains(version) { selected = .current }
        if case .version(let version) = comparedWith, !versions.contains(version) { comparedWith = .current }
        if selected == .current && comparedWith == .current, let original = versions.first {
            selected = .version(original)                       // what changed since it came in
        }
    }

    private func restore() {
        guard case .version(let version) = selected else { return }
        if let restored = model.restore(version, of: cape) {
            cape = restored
            selected = .current
            comparedWith = .current
            reloadVersions()
        }
    }
}

/// The changed details and cursors of a diff, each cursor with both versions side by side.
private struct DiffList: View {
    let diff: CapeDiff

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(diff.details, id: \.label) { change in
                    LabeledContent(change.label) {
                        Text("\(change.old) → \(change.new)")
                            .textSelection(.enabled)
                    }
                }
                if !diff.details.isEmpty && !diff.cursors.isEmpty { Divider() }
                ForEach(diff.cursors) { cursor in
                    HStack(alignment: .center, spacing: 12) {
                        preview(cursor.old)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        preview(cursor.new)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cursor.name)
                                .font(.body.weight(.medium))
                            ForEach(lines(for: cursor.status), id: \.self) { line in
                                Text(line)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .padding(.trailing, 8)
        }
    }

    private func lines(for status: CapeDiff.CursorStatus) -> [String] {
        switch status {
        case .added: [String(localized: "Added")]
        case .removed: [String(localized: "Removed")]
        case .changed(let changes): changes.map(\.description)
        }
    }

    @ViewBuilder
    private func preview(_ cursor: CapeCursor?) -> some View {
        ZStack {
            CheckerboardBackground()
            if let cursor {
                CursorPreview(cursor: cursor, zoom: min(2, 52 / max(cursor.size.width, cursor.size.height, 1)))
            } else {
                Image(systemName: "minus")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
