import SwiftUI
import CapeKit

/// Picks which frames of an animation to keep: for cursors over macOS's frame limit, or
/// to thin out any animation. Original and result play side by side.
struct FrameChooserView: View {
    let cursor: CapeCursor
    let onApply: (CapeCursor) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var preset: Preset
    @State private var kept: Set<Int>
    @State private var frameDuration: Double
    /// Once the duration is typed in, selection changes no longer recompute it.
    @State private var durationEdited = false
    @State private var frames: [CGImage] = []
    @State private var failed = false

    private let limit = CapeCursor.maximumFrameCount

    enum Preset: Hashable {
        case everyNth, spread, first, custom
    }

    init(cursor: CapeCursor, onApply: @escaping (CapeCursor) -> Void) {
        self.cursor = cursor
        self.onApply = onApply
        let initial = FrameSelection.everyNth(of: cursor.frameCount)
        _preset = State(initialValue: .everyNth)
        _kept = State(initialValue: Set(initial))
        _frameDuration = State(initialValue: FrameSelection.loopPreservingDuration(
            frameDuration: cursor.frameDuration, frameCount: cursor.frameCount, kept: initial.count))
    }

    private var keptInOrder: [Int] { kept.sorted() }
    private var isValid: Bool { (1...limit).contains(kept.count) }
    private var isUneven: Bool { FrameSelection.isUneven(keptInOrder, frameCount: cursor.frameCount) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            previews
            Picker("Keep", selection: $preset) {
                Text(everyNthLabel).tag(Preset.everyNth)
                Text("Spread \(min(limit, cursor.frameCount)) evenly").tag(Preset.spread)
                Text("First \(min(limit, cursor.frameCount))").tag(Preset.first)
                Text("Custom").tag(Preset.custom)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            filmstrip
            footer
        }
        .padding(20)
        .frame(minWidth: 720, idealWidth: 760, minHeight: 500, idealHeight: 540)
        .task { frames = await FrameCache.shared.frames(for: cursor, scale: 2) }
        .onChange(of: preset) { _, newValue in applyPreset(newValue) }
        .onChange(of: kept) { _, _ in
            if !durationEdited {
                frameDuration = FrameSelection.loopPreservingDuration(
                    frameDuration: cursor.frameDuration, frameCount: cursor.frameCount, kept: kept.count)
            }
        }
        .alert("Frames not changed", isPresented: $failed) {
            Button("OK") {}
        } message: {
            Text("The images of \(cursor.name) could not be read.")
        }
    }

    // MARK: - Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Choose Frames — \(cursor.name)")
                .font(.title2.weight(.semibold))
            Text("macOS shows at most \(limit) frames of an animation. Pick the ones to keep; by default one loop keeps its length, so the animation runs at the same speed.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var previews: some View {
        HStack(spacing: 24) {
            PreviewBox(title: String(localized: "Original · \(cursor.frameCount) frames"),
                       frames: frames, duration: cursor.frameDuration, aspect: aspect)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            PreviewBox(title: String(localized: "Result · \(kept.count) frames"),
                       frames: keptInOrder.compactMap { frames.indices.contains($0) ? frames[$0] : nil },
                       duration: frameDuration, aspect: aspect)
            Spacer()
        }
    }

    private var filmstrip: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64, maximum: 72), spacing: 8)], spacing: 8) {
                ForEach(0..<cursor.frameCount, id: \.self) { index in
                    FrameCell(image: frames.indices.contains(index) ? frames[index] : nil,
                              index: index, isKept: kept.contains(index), aspect: aspect)
                        .onTapGesture { toggle(index) }
                }
            }
            .padding(2)
        }
        .frame(minHeight: 130)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text("\(kept.count) of \(cursor.frameCount) frames kept · at most \(limit)")
                    .foregroundStyle(isValid ? Color.secondary : Color.red)
                    .monospacedDigit()
                Spacer()
                // A stepper rather than a text field: the sheet gives a text field focus,
                // and a focused field doesn't show the value the selection recomputes.
                Stepper(value: durationBinding, in: 0.001...5, step: 0.001) {
                    Text("\(frameDuration, format: .number.precision(.fractionLength(3))) s per frame")
                        .monospacedDigit()
                }
                .fixedSize()
                Button("Keep Loop Length") {
                    durationEdited = false
                    frameDuration = FrameSelection.loopPreservingDuration(
                        frameDuration: cursor.frameDuration, frameCount: cursor.frameCount, kept: kept.count)
                }
                .disabled(!durationEdited)
            }
            if isUneven && kept.count > 1 {
                Label("The kept frames are unevenly spaced. A cursor has one duration for all frames, so steady motion may stutter. Compare the two previews.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Keep \(kept.count) Frames") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
    }

    // MARK: - Actions

    private var everyNthLabel: String {
        let step = max(1, (cursor.frameCount + limit - 1) / limit)
        guard step > 1 else { return String(localized: "All") }
        // In the language the app is shown in, not the system's: "2nd", not "2."
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        let ordinal = formatter.string(from: step as NSNumber) ?? "\(step)"
        return String(localized: "Every \(ordinal) frame")
    }

    /// Frame height over width, for the preview boxes.
    private var aspect: CGFloat {
        cursor.size.width > 0 ? cursor.size.height / cursor.size.width : 1
    }

    private var durationBinding: Binding<Double> {
        Binding(get: { frameDuration }, set: { frameDuration = max(0.001, $0); durationEdited = true })
    }

    private func applyPreset(_ preset: Preset) {
        switch preset {
        case .everyNth: kept = Set(FrameSelection.everyNth(of: cursor.frameCount))
        case .spread: kept = Set(FrameSelection.spread(of: cursor.frameCount))
        case .first: kept = Set(FrameSelection.first(of: cursor.frameCount))
        case .custom: break
        }
    }

    private func toggle(_ index: Int) {
        if kept.contains(index) { kept.remove(index) } else { kept.insert(index) }
        preset = .custom
    }

    private func apply() {
        guard let result = cursor.keepingFrames(keptInOrder, frameDuration: frameDuration) else {
            failed = true
            return
        }
        onApply(result)
        dismiss()
    }
}

/// An animated preview of a list of frames.
private struct PreviewBox: View {
    let title: String
    let frames: [CGImage]
    let duration: Double
    let aspect: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.animation(minimumInterval: max(duration, 0.01), paused: frames.count < 2)) { context in
                ZStack {
                    CheckerboardBackground()
                    if !frames.isEmpty {
                        let index = Int(context.date.timeIntervalSinceReferenceDate / max(duration, 0.01)) % frames.count
                        Image(decorative: frames[index], scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(1 / aspect, contentMode: .fit)
                            .padding(10)
                    }
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// One frame in the filmstrip; dimmed and unticked when it is dropped.
private struct FrameCell: View {
    let image: CGImage?
    let index: Int
    let isKept: Bool
    let aspect: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    CheckerboardBackground(squareSize: 6)
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(1 / aspect, contentMode: .fit)
                            .padding(4)
                    }
                }
                .opacity(isKept ? 1 : 0.3)
                Image(systemName: isKept ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isKept ? Color.accentColor : .secondary)
                    .background(Circle().fill(.background).padding(2))
                    .padding(3)
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isKept ? Color.accentColor : .secondary.opacity(0.3), lineWidth: isKept ? 2 : 1)
            }
            Text(verbatim: "\(index + 1)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Frame \(index + 1)")
        .accessibilityValue(isKept ? "kept" : "dropped")
        .accessibilityAddTraits(.isButton)
    }
}
