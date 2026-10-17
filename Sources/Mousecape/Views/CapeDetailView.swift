import SwiftUI
import CapeKit

/// One cape: its metadata, an apply button and every cursor it replaces.
struct CapeDetailView: View {
    let cape: Cape
    let isApplied: Bool
    /// Cursors with problems, by identifier.
    let problems: [String: [CursorProblem]]
    let onApply: () -> Void
    let onEdit: () -> Void

    @AppStorage("showsHotSpots") private var showsHotSpots = false

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !problems.isEmpty {
                    ProblemBanner(cape: cape, problems: problems, onEdit: onEdit)
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(cape.cursors) { cursor in
                        CursorTile(cursor: cursor, showsHotSpot: showsHotSpots,
                                   problems: problems[cursor.identifier] ?? [])
                    }
                }
                // Fresh tiles per cape: capes share cursor identifiers, and reused tiles
                // would show the previous cape's images until the new ones are decoded.
                .id(cape.id)
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $showsHotSpots) {
                    Label("Show Hot Spots", systemImage: "scope")
                }
                .help("Mark where each cursor clicks")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(cape.name)
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit…", action: onEdit)
                .controlSize(.large)
            if isApplied {
                Label("Applied", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                Button("Apply", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !cape.author.isEmpty { parts.append(cape.author) }
        parts.append(String(localized: "Version \(cape.version.formatted())"))
        parts.append(String(localized: "\(cape.cursors.count) cursors"))
        if cape.isHiDPI { parts.append("HiDPI") }
        return parts.joined(separator: " · ")
    }
}

/// What is wrong with which cursor, and the way to the editor.
private struct ProblemBanner: View {
    let cape: Cape
    let problems: [String: [CursorProblem]]
    let onEdit: () -> Void

    private var hasErrors: Bool { problems.values.joined().contains(where: \.isError) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProblemBadge(problems: Array(problems.values.joined()))
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(hasErrors ? "Some cursors won't apply correctly" : "Some cursors are adjusted when applied")
                    .font(.headline)
                ForEach(affected) { cursor in
                    Text("**\(cursor.name):** \((problems[cursor.identifier] ?? []).map(\.description).joined(separator: " "))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Edit…", action: onEdit)
        }
        .padding(12)
        .background((hasErrors ? Color.red : Color.orange).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private var affected: [CapeCursor] {
        cape.cursors.filter { problems[$0.identifier] != nil }
    }
}

private struct CursorTile: View {
    let cursor: CapeCursor
    let showsHotSpot: Bool
    let problems: [CursorProblem]

    var body: some View {
        VStack(spacing: 8) {
            CursorPreview(cursor: cursor, zoom: zoom, showsHotSpot: showsHotSpot)
                .frame(width: 96, height: 96)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    if !problems.isEmpty {
                        ProblemBadge(problems: problems)
                            .padding(6)
                            .help(problems.map(\.description).joined(separator: "\n"))
                    }
                }
            VStack(spacing: 2) {
                Text(cursor.name)
                    .font(.callout)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .help(cursor.identifier)
    }

    /// Twice the real size, but never larger than the tile.
    private var zoom: CGFloat {
        min(2, 80 / max(cursor.size.width, cursor.size.height))
    }

    private var detail: String {
        cursor.isAnimated
            ? String(localized: "\(cursor.frameCount) frames")
            : "\(Int(cursor.size.width)) × \(Int(cursor.size.height)) pt"
    }
}

/// Red for errors, orange when macOS only adjusts the cursor.
struct ProblemBadge: View {
    let problems: [CursorProblem]

    /// "1 cursor needs attention" / "3 cursors need attention".
    static func summary(cursorCount: Int) -> String {
        cursorCount == 1
            ? String(localized: "1 cursor needs attention")
            : String(localized: "\(cursorCount) cursors need attention")
    }

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(problems.contains(where: \.isError) ? .red : .orange)
            .accessibilityLabel(problems.contains(where: \.isError) ? "Error" : "Warning")
    }
}
