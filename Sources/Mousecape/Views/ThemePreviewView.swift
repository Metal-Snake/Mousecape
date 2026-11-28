import SwiftUI
import CapeKit

/// Shows what a gallery theme's cursors look like once installed: its files are downloaded
/// and converted as Install would, but nothing is saved. The pictures on pling.com don't
/// always show the cursors. With several versions, a picker switches between them; Install
/// takes the one shown.
struct ThemePreviewView: View {
    let model: AppModel
    let theme: PlingTheme
    /// The files to preview: one from the details, or all that Install would take.
    let files: [PlingTheme.File]
    /// Called after the shown version was installed.
    let onInstalled: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var choice: ThemeChoice?
    @State private var selectedID: ThemeOption.ID?
    @State private var failure: String?
    @AppStorage("showsHotSpots") private var showsHotSpots = false

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 16)]

    private var selected: ThemeOption? {
        choice?.options.first { $0.id == selectedID } ?? choice?.options.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 12)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
                .padding(12)
        }
        .frame(minWidth: 640, idealWidth: 760, maxWidth: .infinity, minHeight: 460, idealHeight: 600, maxHeight: .infinity)
        .resizableSheet(minWidth: 640, minHeight: 460, sizeKey: "themePreview")
        .dismissesOnOutsideClick()
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Preview — \(theme.name)")
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Toggle("Show Hot Spots", isOn: $showsHotSpots)
                    .help("Mark where each cursor clicks")
            }
            HStack {
                // Version names can be long (folder, kind and file): the picker shrinks
                // with the sheet rather than widening it.
                if let choice, choice.options.count > 1 {
                    Picker("Version", selection: Binding { selectedID ?? choice.options.first?.id } set: { selectedID = $0 }) {
                        ForEach(choice.options) { option in
                            Text(label(of: option, among: choice.options)).tag(Optional(option.id))
                        }
                    }
                    .frame(maxWidth: 460)
                }
                if let selected {
                    Text(summary(of: selected))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if let failure {
            ContentUnavailableView {
                Label("No Preview", systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure)
            }
        } else if let selected {
            let problems = selected.cape.problems(leftHanded: EnginePreferences.leftHanded,
                                                  longAnimations: Engine.longAnimations)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(selected.cape.cursors) { cursor in
                        CursorTile(cursor: cursor, showsHotSpot: showsHotSpots,
                                   problems: problems[cursor.identifier] ?? [])
                    }
                }
                .padding(20)
                // Fresh tiles per version: they share cursor identifiers.
                .id(selected.id)
            }
        } else {
            VStack(spacing: 10) {
                ProgressView()
                Text("Downloading and converting…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let selected, !selected.skipped.isEmpty {
                Text("Left out, as macOS has no matching cursor: \(selected.skipped.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Install") {
                guard let selected else { return }
                model.install([selected])
                dismiss()
                onInstalled()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selected == nil)
        }
    }

    /// What tells a version apart in the picker: its folder in the archive, its kind and,
    /// with several files, the file.
    private func label(of option: ThemeOption, among options: [ThemeOption]) -> String {
        var parts: [String] = []
        if let variant = option.variant, !variant.isEmpty { parts.append(variant) }
        parts.append(option.kind.shortTitle)
        if Set(options.map(\.fileName)).count > 1 { parts.append(option.fileName) }
        return parts.joined(separator: " · ")
    }

    private func summary(of option: ThemeOption) -> String {
        var parts = [String(localized: "\(option.cape.cursors.count) cursors")]
        if option.cape.isHiDPI { parts.append("HiDPI") }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        do {
            let options = try await model.galleryVersions(of: files, of: theme)
            // The suggested version first, as when installing.
            let loaded = ThemeChoice(title: theme.name, options: options)
            choice = loaded
            selectedID = loaded.options.first?.id
        } catch is CancellationError {
            // The sheet was closed while downloading.
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// A theme and the files to preview, for the gallery's preview sheet.
struct PreviewRequest: Identifiable {
    let id = UUID()
    let theme: PlingTheme
    let files: [PlingTheme.File]
}
