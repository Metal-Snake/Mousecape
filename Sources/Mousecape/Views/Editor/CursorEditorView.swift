import SwiftUI
import UniformTypeIdentifiers
import CapeKit

/// Edits one cursor: preview with hot spot, geometry, animation, and one image per scale.
struct CursorEditorView: View {
    @Binding var cursor: CapeCursor

    @State private var importError: String?

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
                problems
            }
            .padding(20)
        }
        .alert("Image not added", isPresented: Binding(get: { importError != nil },
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
                CursorPreview(cursor: cursor, zoom: zoom, showsHotSpot: true)
                    .overlay {
                        // Clicking inside the cursor moves the hot spot there.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(coordinateSpace: .local) { location in
                                cursor.hotSpot = CGPoint(x: (location.x / zoom).rounded(),
                                                         y: (location.y / zoom).rounded())
                            }
                    }
                    .border(Color.accentColor.opacity(0.35), width: 1)
            }
            .frame(width: previewBox, height: previewBox)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("Click to set the hot spot")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                Stepper(value: $cursor.frameCount, in: 1...CapeCursor.maximumFrameCount) {
                    Text("\(cursor.frameCount)")
                        .monospacedDigit()
                }
            }
            LabeledContent("Frame duration") {
                HStack {
                    TextField("Seconds", value: $cursor.frameDuration, format: .number.precision(.fractionLength(0...3)))
                        .frame(width: 70)
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
            .frame(width: 56)
            .multilineTextAlignment(.trailing)
    }

    // MARK: - Images per scale

    private var imageWells: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Images")
                .font(.headline)
            Text("Drop a PNG per pixel density. Animated cursors stack all frames vertically, first frame on top.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                ForEach(CapeCursor.supportedScales, id: \.self) { scale in
                    ImageWell(scale: scale,
                              image: cursor.representation(for: scale),
                              expected: cursor.expectedPixelSize(for: scale),
                              onDrop: { url in addImage(from: url, scale: scale) },
                              onChoose: { chooseImage(scale: scale) },
                              onRemove: { cursor.setRepresentation(nil, for: scale) })
                }
            }
        }
    }

    @ViewBuilder
    private var problems: some View {
        let problems = cursor.problems
        if !problems.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                    Label(problem.description, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.callout)
        }
    }

    private func chooseImage(scale: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = String(localized: "Choose the \(scale)x image for \(cursor.name)")
        if panel.runModal() == .OK, let url = panel.url {
            addImage(from: url, scale: scale)
        }
    }

    private func addImage(from url: URL, scale: Int) {
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
    let expected: CGSize
    let onDrop: (URL) -> Void
    let onChoose: () -> Void
    let onRemove: () -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if let image, let nsImage = NSImage(data: image) {
                    CheckerboardBackground()
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(6)
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
            Text("\(Int(expected.width)) × \(Int(expected.height)) px")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .help("Drop an image, double-click to choose one, right-click to remove")
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
