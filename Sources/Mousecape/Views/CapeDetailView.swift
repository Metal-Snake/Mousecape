import SwiftUI
import CapeKit

/// One cape: its metadata, an apply button and every cursor it replaces.
struct CapeDetailView: View {
    let cape: Cape
    let isApplied: Bool
    let onApply: () -> Void

    @AppStorage("showsHotSpots") private var showsHotSpots = false

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(cape.cursors) { cursor in
                        CursorTile(cursor: cursor, showsHotSpot: showsHotSpots)
                    }
                }
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

private struct CursorTile: View {
    let cursor: CapeCursor
    let showsHotSpot: Bool

    var body: some View {
        VStack(spacing: 8) {
            CursorPreview(cursor: cursor, zoom: zoom, showsHotSpot: showsHotSpot)
                .frame(width: 96, height: 96)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
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
