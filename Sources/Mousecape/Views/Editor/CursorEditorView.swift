import SwiftUI
import UniformTypeIdentifiers
import CapeKit

/// Edits one cursor: preview with hot spot, geometry, animation, one image per scale, and
/// how it looks in left-handed mode.
struct CursorEditorView: View {
    @Binding var cursor: CapeCursor
    /// The cursor's problems within its cape (left-handed hints included).
    let problems: [CursorProblem]

    @State private var importError: String?
    @State private var choosingFrames = false
    /// Shows the cursor as left-handed mode does.
    @State private var previewLeftHanded = false
    /// The cursor as left-handed mode shows it, worked out once per change.
    @State private var leftHandedCursor: CapeCursor?

    private let previewBox: CGFloat = 200

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                HStack(alignment: .top, spacing: 24) {
                    preview
                    geometryForm
                }
                imageWells
                leftHandedSection
                problemList
            }
            .padding(20)
        }
        .sheet(isPresented: $choosingFrames) {
            FrameChooserView(cursor: cursor) { cursor = $0 }
        }
        .alert("Cursor not changed", isPresented: Binding(get: { importError != nil },
                                                      set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cursor.name)
                .font(.title2.weight(.semibold))
            Text(cursor.identifier)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Preview and hot spot

    private var zoom: CGFloat {
        let largest = max(cursor.size.width, cursor.size.height)
        return largest > 0 ? min(6, (previewBox - 16) / largest) : 1
    }

    private var preview: some View {
        VStack(spacing: 6) {
            ZStack {
                CheckerboardBackground()
                CursorPreview(cursor: previewLeftHanded ? (leftHandedCursor ?? cursor) : cursor,
                              zoom: zoom, showsHotSpot: true)
                    .overlay {
                        // Clicking inside the cursor moves the hot spot there.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(coordinateSpace: .local) { location in
                                setHotSpot(CGPoint(x: (location.x / zoom).rounded(), y: (location.y / zoom).rounded()))
                            }
                    }
                    .border(Color.accentColor.opacity(0.35), width: 1)
            }
            .frame(width: previewBox, height: previewBox)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("Click to set the hot spot")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Left-handed", isOn: $previewLeftHanded)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)
                .help("Show the cursor as left-handed mode does")
        }
        .task(id: cursor) { leftHandedCursor = cursor.leftHanded }
    }

    /// A click in the preview: in the left-handed preview it sets the left-handed hot spot
    /// (own images) or the hot spot it mirrors from.
    private func setHotSpot(_ point: CGPoint) {
        guard previewLeftHanded else { cursor.hotSpot = point; return }
        switch cursor.leftHandedLook {
        case .ownImages: cursor.leftHandedHotSpot = point
        case .mirrored: cursor.hotSpot = CGPoint(x: cursor.size.width - point.x - 1, y: point.y)
        case .unchanged: cursor.hotSpot = point
        }
    }

    // MARK: - Geometry and animation

    private var geometryForm: some View {
        Form {
            LabeledContent("Size (points)") {
                HStack {
                    numberField("Width", value: $cursor.size.width)
                    Text("×")
                    numberField("Height", value: $cursor.size.height)
                }
            }
            LabeledContent("Hot spot") {
                HStack {
                    numberField("X", value: $cursor.hotSpot.x)
                    Text(",")
                    numberField("Y", value: $cursor.hotSpot.y)
                }
            }
            LabeledContent("Frames") {
                if cursor.frameCount > CapeCursor.maximumFrameCount {
                    // More than macOS takes: only reducing makes sense, not stepping.
                    HStack {
                        Text("\(cursor.frameCount)")
                            .monospacedDigit()
                        Button("Reduce to \(cursor.appliedFrameCount)", action: reduceFrames)
                        Button("Choose…") { choosingFrames = true }
                            .help("Pick which frames to keep")
                    }
                } else {
                    HStack {
                        Stepper(value: $cursor.frameCount, in: 1...CapeCursor.maximumFrameCount) {
                            Text("\(cursor.frameCount)")
                                .monospacedDigit()
                        }
                        if cursor.isAnimated && !cursor.representations.isEmpty {
                            Button("Choose…") { choosingFrames = true }
                                .help("Pick which frames to keep")
                        }
                    }
                }
            }
            LabeledContent("Frame duration") {
                HStack {
                    TextField("Seconds", value: $cursor.frameDuration, format: .number.precision(.fractionLength(0...3)))
                        .labelsHidden()
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                    Text("s")
                }
            }
            .disabled(cursor.frameCount < 2)
        }
        .formStyle(.columns)
    }

    private func numberField(_ title: LocalizedStringKey, value: Binding<CGFloat>) -> some View {
        let double = Binding<Double>(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = CGFloat($0) })
        return TextField(title, value: double, format: .number.precision(.fractionLength(0...1)))
            .labelsHidden()
            .frame(width: 60)
            .multilineTextAlignment(.trailing)
    }

    // MARK: - Images per scale

    private var imageWells: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Images")
                .font(.headline)
            Text("Drop a PNG per pixel density. Animated cursors stack all frames vertically, first frame on top. A Windows .cur or .ani replaces the whole cursor.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                ForEach(CapeCursor.supportedScales, id: \.self) { scale in
                    ImageWell(scale: scale,
                              image: cursor.representation(for: scale),
                              frameCount: cursor.frameCount,
                              expected: cursor.expectedPixelSize(for: scale),
                              onDrop: { url in addImage(from: url, scale: scale) },
                              onChoose: { chooseImage(scale: scale) },
                              onRemove: { cursor.setRepresentation(nil, for: scale) })
                }
            }
        }
    }

    // MARK: - Left-handed mode

    private enum LeftHandedMode: Hashable {
        case automatic, mirror, dontMirror, ownImages
    }

    private var leftHandedMode: Binding<LeftHandedMode> {
        Binding {
            if cursor.hasOwnLeftHandedImages { return .ownImages }
            switch cursor.mirrorForLeftHanded {
            case true?: return .mirror
            case false?: return .dontMirror
            case nil: return .automatic
            }
        } set: { mode in
            // One change to the cursor, not several: the mode is read back from the result.
            var changed = cursor
            changed.leftHandedRepresentations = []
            changed.leftHandedHotSpot = nil
            switch mode {
            case .automatic: changed.mirrorForLeftHanded = nil
            case .mirror: changed.mirrorForLeftHanded = true
            case .dontMirror: changed.mirrorForLeftHanded = false
            case .ownImages:
                changed.mirrorForLeftHanded = nil
                if !changed.useMirroredImagesAsLeftHanded() {
                    importError = String(localized: "The images of \(cursor.name) could not be read, so they could not be mirrored.")
                    return
                }
            }
            cursor = changed
        }
    }

    private var leftHandedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Left-handed mode")
                .font(.headline)
            Picker("Left-handed mode", selection: leftHandedMode) {
                Text(CursorNames.isPointer(cursor.identifier) ? "Automatic (Mirror)" : "Automatic (Don't Mirror)")
                    .tag(LeftHandedMode.automatic)
                Text("Mirror").tag(LeftHandedMode.mirror)
                Text("Don't Mirror").tag(LeftHandedMode.dontMirror)
                Text("Own Images").tag(LeftHandedMode.ownImages)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Text(leftHandedExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if cursor.hasOwnLeftHandedImages {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(CapeCursor.supportedScales, id: \.self) { scale in
                        ImageWell(scale: scale,
                                  image: cursor.leftHandedRepresentation(for: scale),
                                  frameCount: cursor.frameCount,
                                  expected: cursor.expectedPixelSize(for: scale),
                                  onDrop: { url in addLeftHandedImage(from: url, scale: scale) },
                                  onChoose: { chooseImage(scale: scale, leftHanded: true) },
                                  onRemove: { cursor.setLeftHandedRepresentation(nil, for: scale) })
                    }
                }
                LabeledContent("Left-handed hot spot") {
                    HStack {
                        numberField("X", value: leftHandedHotSpot.x)
                        Text(",")
                        numberField("Y", value: leftHandedHotSpot.y)
                    }
                }
                .fixedSize()
            }
        }
    }

    private var leftHandedExplanation: String {
        switch leftHandedMode.wrappedValue {
        case .automatic:
            String(localized: "Pointers (arrow, hands, busy and the like) are mirrored, the others are left as they are.")
        case .mirror:
            String(localized: "Mirrored in left-handed mode, hot spot included, e.g. for an I-beam drawn as an arrow.")
        case .dontMirror:
            String(localized: "Left as it is in left-handed mode, e.g. for symmetric artwork or artwork with text.")
        case .ownImages:
            String(localized: "These images are shown in left-handed mode instead. They start as the mirrored images; replace the ones where mirroring looks wrong (text, a hand, a shadow cast to one side).")
        }
    }

    private var leftHandedHotSpot: Binding<CGPoint> {
        Binding(get: { cursor.leftHandedHotSpot ?? cursor.mirroredHotSpot },
                set: { cursor.leftHandedHotSpot = $0 })
    }

    private func addLeftHandedImage(from url: URL, scale: Int) {
        guard let data = try? Data(contentsOf: url),
              let (png, pixels) = CapeCursor.normalizedPNG(from: data) else {
            importError = String(localized: "“\(url.lastPathComponent)” is not an image Mousecape can read.")
            return
        }
        let expected = cursor.expectedPixelSize(for: scale)
        guard pixels == expected else {
            importError = String(localized: "The \(scale)x image must be \(Int(expected.width)) × \(Int(expected.height)) px; “\(url.lastPathComponent)” is \(Int(pixels.width)) × \(Int(pixels.height)) px.")
            return
        }
        cursor.setLeftHandedRepresentation(png, for: scale)
    }

    @ViewBuilder
    private var problemList: some View {
        if !problems.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                    Label(problem.description, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(problem.isError ? .red : .orange)
                }
            }
            .font(.callout)
        }
    }

    /// Keeps every n-th frame for good, the way the engine would when applying.
    private func reduceFrames() {
        if let reduced = cursor.reducingFrames() {
            cursor = reduced
        } else {
            importError = String(localized: "The images of \(cursor.name) could not be read, so its frames were not reduced.")
        }
    }

    private func chooseImage(scale: Int, leftHanded: Bool = false) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = leftHanded ? [.image] : [.image] + ["cur", "ani"].compactMap { UTType(filenameExtension: $0) }
        panel.message = leftHanded ? String(localized: "Choose the left-handed \(scale)x image for \(cursor.name)")
                                   : String(localized: "Choose the \(scale)x image for \(cursor.name)")
        if panel.runModal() == .OK, let url = panel.url {
            if leftHanded { addLeftHandedImage(from: url, scale: scale) } else { addImage(from: url, scale: scale) }
        }
    }

    private func addImage(from url: URL, scale: Int) {
        // A Windows or Xcursor file replaces the whole cursor: images, size, hot spot and frames.
        let isWindows = ThemeImport.windowsExtensions.contains(url.pathExtension.lowercased())
        if isWindows || ThemeImport.isLooseXcursor(url) {
            do {
                let data = try Data(contentsOf: url)
                cursor = isWindows ? try WindowsCursor.capeCursor(from: data, identifier: cursor.identifier)
                                   : try Xcursor.capeCursor(from: data, identifier: cursor.identifier)
            } catch {
                importError = "“\(url.lastPathComponent)”: \(error.localizedDescription)"
            }
            return
        }
        guard let data = try? Data(contentsOf: url),
              let (png, pixels) = CapeCursor.normalizedPNG(from: data) else {
            importError = String(localized: "“\(url.lastPathComponent)” is not an image Mousecape can read.")
            return
        }
        // The first image of a cursor defines its size; later ones must fit it.
        if cursor.representations.isEmpty {
            cursor.size = CGSize(width: pixels.width / Double(scale),
                                 height: pixels.height / Double(scale) / Double(cursor.frameCount))
        }
        let expected = cursor.expectedPixelSize(for: scale)
        guard pixels == expected else {
            importError = String(localized: "The \(scale)x image must be \(Int(expected.width)) × \(Int(expected.height)) px; “\(url.lastPathComponent)” is \(Int(pixels.width)) × \(Int(pixels.height)) px.")
            return
        }
        cursor.setRepresentation(png, for: scale)
    }
}

/// One drop target for the image at a pixel density.
private struct ImageWell: View {
    let scale: Int
    let image: Data?
    let frameCount: Int
    let expected: CGSize
    let onDrop: (URL) -> Void
    let onChoose: () -> Void
    let onRemove: () -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if let firstFrame {
                    CheckerboardBackground()
                    Image(decorative: firstFrame, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(6)
                    if frameCount > 1 {
                        Text("\(frameCount) frames")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.regularMaterial, in: Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(5)
                    }
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 110, height: 110)
            .background(.quaternary.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isTargeted ? Color.accentColor : .secondary.opacity(0.3),
                                  style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: image == nil ? [4] : []))
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                onDrop(url)
                return true
            } isTargeted: { isTargeted = $0 }
            .contextMenu {
                Button("Choose Image…", action: onChoose)
                Button("Remove", role: .destructive, action: onRemove)
                    .disabled(image == nil)
            }
            .onTapGesture(count: 2, perform: onChoose)

            Text("\(scale)x")
                .font(.callout.weight(.medium))
            Text(verbatim: "\(Int(expected.width)) × \(Int(expected.height)) px")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .help("Drop an image, double-click to choose one, right-click to remove")
    }

    /// The top frame of the sheet, so tall animated sheets don't shrink to a sliver.
    private var firstFrame: CGImage? {
        guard let image, let sheet = NSBitmapImageRep(data: image)?.cgImage else { return nil }
        let height = sheet.height / max(frameCount, 1)
        return sheet.cropping(to: CGRect(x: 0, y: 0, width: sheet.width, height: max(height, 1))) ?? sheet
    }
}

/// The usual transparency checkerboard.
struct CheckerboardBackground: View {
    var squareSize: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            let columns = Int(size.width / squareSize) + 1
            let rows = Int(size.height / squareSize) + 1
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * squareSize, y: CGFloat(row) * squareSize,
                                      width: squareSize, height: squareSize)
                    context.fill(Path(rect), with: .color(.secondary.opacity(0.12)))
                }
            }
        }
    }
}
