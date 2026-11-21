import SwiftUI
import CapeKit

/// Asks which version of a theme to install when it offers several: several files (Linux
/// and Windows), or one archive with a Regular, a Large and an Extra-Large version. It shows
/// how they differ rather than only naming them: a few cursors of each at their real size,
/// and the facts about each, with those that differ in bold. A suggestion is selected.
struct ThemeChoiceView: View {
    let choice: ThemeChoice
    /// Whether a version is in the library already.
    var isInstalled: (ThemeOption) -> Bool = { _ in false }
    let onChoose: (ThemeOption) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: ThemeOption.ID?

    /// The cursors each version shows, side by side: the everyday ones.
    static let sampleCursors = ["com.apple.coregraphics.Arrow", "com.apple.coregraphics.IBeam",
                                "com.apple.cursor.13", "com.apple.coregraphics.Move", "com.apple.coregraphics.Wait"]

    private var differences: CapeSummary.Differences {
        CapeSummary.differences(among: choice.options.map(\.summary))
    }

    /// All rows give their cursors the same height, the largest, so sizes compare.
    private var sampleHeight: CGFloat {
        choice.options.flatMap { option in
            option.cape.cursors.filter { Self.sampleCursors.contains($0.identifier) }.map(\.size.height)
        }.max() ?? 24
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Which Version of “\(choice.title)”?")
                    .font(.title2.weight(.semibold))
                Text(explanation)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(choice.options.enumerated()), id: \.element.id) { index, option in
                        OptionRow(option: option, differences: differences, sampleHeight: sampleHeight,
                                  isSelected: selection == option.id, isSuggested: index == choice.suggested,
                                  isInstalled: isInstalled(option))
                            .onTapGesture(count: 2) { choose(option) }
                            .onTapGesture { selection = option.id }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Install") {
                    if let option = choice.options.first(where: { $0.id == selection }) { choose(option) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 660, idealWidth: 720, minHeight: 420, idealHeight: 580)
        .onAppear {
            selection = choice.suggested.map { choice.options[$0].id } ?? choice.options.first?.id
        }
    }

    /// Says what tells the versions apart, in words.
    private var explanation: String {
        var parts: [String] = []
        if differences.contains(.cursorCount) { parts.append(String(localized: "how many cursors they have")) }
        if differences.contains(.size) { parts.append(String(localized: "size")) }
        if differences.contains(.sharpness) { parts.append(String(localized: "sharpness on Retina displays")) }
        if differences.contains(.animation) { parts.append(String(localized: "animation")) }
        let count = choice.options.count
        guard !parts.isEmpty else {
            return String(localized: "It comes in \(count) versions that look the same to Mousecape; they may differ only in what macOS has no place for.")
        }
        let list = parts.formatted(.list(type: .and))
        return String(localized: "It comes in \(count) versions. They differ in \(list): what differs is in bold, and the cursors are shown at their real size.")
    }

    private func choose(_ option: ThemeOption) {
        dismiss()
        onChoose(option)
    }
}

/// One version: its name and origin, a few cursors at their real size, and its facts.
private struct OptionRow: View {
    let option: ThemeOption
    let differences: CapeSummary.Differences
    let sampleHeight: CGFloat
    let isSelected: Bool
    let isSuggested: Bool
    let isInstalled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .font(.title3)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(option.cape.name)
                        .font(.headline)
                    if isSuggested { Tag(text: String(localized: "Suggested"), color: .blue) }
                    if isInstalled { Tag(text: String(localized: "Installed"), color: .green) }
                }
                Text(origin)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                samples
                facts
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.quaternary.opacity(0.4)),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private var origin: String {
        var text = "\(option.kind.title) · \(option.fileName)"
        if let variant = option.variant { text += " → \(variant)" }
        return text
    }

    /// The sample cursors at their real size; a dash where the version has none.
    private var samples: some View {
        HStack(alignment: .bottom, spacing: 16) {
            ForEach(ThemeChoiceView.sampleCursors, id: \.self) { identifier in
                Group {
                    if let cursor = option.cape.cursors.first(where: { $0.identifier == identifier }) {
                        CursorPreview(cursor: cursor)
                            .help("\(cursor.name), \(Int(cursor.size.width)) × \(Int(cursor.size.height)) pt")
                    } else {
                        Text("–")
                            .foregroundStyle(.tertiary)
                            .help(String(localized: "\(CursorNames.name(for: identifier)): not in this version"))
                    }
                }
                .frame(height: sampleHeight, alignment: .bottom)
            }
        }
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 6))
    }

    private var facts: some View {
        let summary = option.summary
        return HStack(spacing: 6) {
            Fact(text: String(localized: "\(summary.cursorCount) cursors"), stands: differences.contains(.cursorCount))
            Text("·").foregroundStyle(.tertiary)
            Fact(text: summary.arrowSize.map { String(localized: "Arrow \(Int($0.width)) × \(Int($0.height)) pt") }
                     ?? String(localized: "No arrow"),
                 stands: differences.contains(.size))
            Text("·").foregroundStyle(.tertiary)
            Fact(text: summary.sharpestScale >= 2 ? String(localized: "Sharp on Retina (\(summary.sharpestScale)x)")
                                                  : String(localized: "Soft on Retina (1x only)"),
                 stands: differences.contains(.sharpness))
            Text("·").foregroundStyle(.tertiary)
            Fact(text: summary.animatedCount == 0 ? String(localized: "Not animated")
                                                  : String(localized: "\(summary.animatedCount) animated"),
                 stands: differences.contains(.animation))
            if !option.skipped.isEmpty {
                Text("·").foregroundStyle(.tertiary)
                Fact(text: String(localized: "\(option.skipped.count) left out"), stands: false)
                    .help(String(localized: "Left out, as macOS has no matching cursor: \(option.skipped.joined(separator: ", "))"))
            }
        }
        .font(.callout)
    }
}

/// A fact about a version; bold when the versions differ in it.
private struct Fact: View {
    let text: String
    /// Whether it tells this version apart from the others.
    let stands: Bool

    var body: some View {
        Text(text)
            .fontWeight(stands ? .semibold : .regular)
            .foregroundStyle(stands ? .primary : .secondary)
    }
}

private struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(color, in: Capsule())
    }
}
