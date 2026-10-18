import Foundation

/// An animated Windows cursor (`.ani`): a RIFF file of type ACON with a header (`anih`),
/// optional per-step rates (`rate`) and frame order (`seq `), and the frames as `.cur`/`.ico`
/// files in a `LIST fram` chunk.
struct WindowsAnimation {
    /// The images of each frame (each frame is a whole `.cur` file).
    var frames: [[WindowsIconImage]]
    /// Frame index shown at each step.
    var steps: [Int]
    /// Duration of each step in jiffies (1/60 s).
    var rates: [Int]
}

enum WindowsAni {
    static func parse(_ data: Data) throws -> WindowsAnimation {
        var reader = ByteReader(data)
        guard try reader.tag() == "RIFF" else { throw WindowsCursorError.notACursor }
        _ = try reader.u32()
        guard try reader.tag() == "ACON" else { throw WindowsCursorError.notACursor }

        var frameCount = 0, stepCount = 0, defaultRate = 0
        var containsIcons = true
        var rates: [Int]?
        var sequence: [Int]?
        var frames: [[WindowsIconImage]] = []

        func readChunks(until end: Int) throws {
            while reader.position + 8 <= end {
                let id = try reader.tag()
                let size = Int(try reader.u32())
                let bodyStart = reader.position
                guard size >= 0, bodyStart + size <= reader.bytes.count else { throw WindowsCursorError.notACursor }
                switch id {
                case "LIST":
                    _ = try reader.tag()                    // "fram" or "INFO"
                    try readChunks(until: bodyStart + size)
                case "anih":
                    _ = try reader.u32()                    // header size
                    frameCount = Int(try reader.u32())
                    stepCount = Int(try reader.u32())
                    _ = try reader.u32(); _ = try reader.u32() // width, height (raw frames only)
                    _ = try reader.u32(); _ = try reader.u32() // bit count, planes
                    defaultRate = Int(try reader.u32())
                    containsIcons = try reader.u32() & 1 != 0
                case "rate":
                    rates = try (0..<size / 4).map { _ in Int(try reader.u32()) }
                case "seq ":
                    sequence = try (0..<size / 4).map { _ in Int(try reader.u32()) }
                case "icon":
                    guard containsIcons else { throw WindowsCursorError.unsupportedImage("raw .ani frames") }
                    frames.append(try WindowsIcon.images(from: try reader.data(count: size)))
                default:
                    break
                }
                reader.position = bodyStart + size + (size & 1)  // chunks are word aligned
            }
        }
        try readChunks(until: reader.bytes.count)

        guard !frames.isEmpty else { throw WindowsCursorError.notACursor }
        if frameCount == 0 { frameCount = frames.count }
        let steps = (sequence ?? Array(0..<(stepCount > 0 ? stepCount : frames.count)))
            .map { min(max($0, 0), frames.count - 1) }
        let stepRates = (rates ?? []).count == steps.count
            ? rates!
            : Array(repeating: max(defaultRate, 1), count: steps.count)
        return WindowsAnimation(frames: frames, steps: steps, rates: stepRates.map { max($0, 1) })
    }
}
