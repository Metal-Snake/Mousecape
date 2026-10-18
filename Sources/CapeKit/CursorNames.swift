/// Human-readable names of the system cursor identifiers, after the names macOS gives the
/// cursor resources (HIServices `cursors/`, SkyLight). The original Mousecape's names
/// ("Camera", "Link", "Busy", …) described some cursors wrongly. Cursors marked "Legacy" are
/// the small coregraphics placeholders macOS keeps next to the real ones.
public enum CursorNames {
    public static let all: [String: String] = [
        "com.apple.coregraphics.Arrow": "Arrow",
        "com.apple.coregraphics.ArrowS": "Arrow S",
        "com.apple.coregraphics.IBeam": "I-Beam",
        "com.apple.coregraphics.IBeamS": "I-Beam S",
        "com.apple.coregraphics.IBeamXOR": "I-Beam XOR (Legacy)",
        "com.apple.coregraphics.Alias": "Alias (Legacy)",
        "com.apple.coregraphics.Copy": "Copy (Legacy)",
        "com.apple.coregraphics.ArrowCtx": "Contextual Menu (Legacy)",
        "com.apple.coregraphics.Move": "Move",
        "com.apple.coregraphics.Wait": "Wait",
        "com.apple.coregraphics.Empty": "Empty",
        "com.apple.cursor.2": "Make Alias",
        "com.apple.cursor.3": "Not Allowed",
        "com.apple.cursor.4": "Busy but Clickable",
        "com.apple.cursor.5": "Copy",
        "com.apple.cursor.7": "Crosshair",
        "com.apple.cursor.8": "Crosshair 2",
        "com.apple.cursor.9": "Screenshot Selection",
        "com.apple.cursor.10": "Screenshot Window",
        "com.apple.cursor.11": "Closed Hand",
        "com.apple.cursor.12": "Open Hand",
        "com.apple.cursor.13": "Pointing Hand",
        "com.apple.cursor.14": "Counting Up Hand",
        "com.apple.cursor.15": "Counting Down Hand",
        "com.apple.cursor.16": "Counting Up and Down Hand",
        "com.apple.cursor.17": "Resize Left",
        "com.apple.cursor.18": "Resize Right",
        "com.apple.cursor.19": "Resize Left-Right",
        "com.apple.cursor.20": "Cell XOR",
        "com.apple.cursor.21": "Resize Up",
        "com.apple.cursor.22": "Resize Down",
        "com.apple.cursor.23": "Resize Up-Down",
        "com.apple.cursor.24": "Contextual Menu",
        "com.apple.cursor.25": "Poof",
        "com.apple.cursor.26": "I-Beam Vertical",
        "com.apple.cursor.27": "Resize East",
        "com.apple.cursor.28": "Resize East-West",
        "com.apple.cursor.29": "Resize Northeast",
        "com.apple.cursor.30": "Resize Northeast-Southwest",
        "com.apple.cursor.31": "Resize North",
        "com.apple.cursor.32": "Resize North-South",
        "com.apple.cursor.33": "Resize Northwest",
        "com.apple.cursor.34": "Resize Northwest-Southeast",
        "com.apple.cursor.35": "Resize Southeast",
        "com.apple.cursor.36": "Resize South",
        "com.apple.cursor.37": "Resize Southwest",
        "com.apple.cursor.38": "Resize West",
        "com.apple.cursor.39": "Resize Square",
        "com.apple.cursor.40": "Help",
        "com.apple.cursor.41": "Cell",
        "com.apple.cursor.42": "Zoom In",
        "com.apple.cursor.43": "Zoom Out",
    ]

    /// The cursors people notice most, shown first in a cape's cursor list.
    static let prominent = [
        "com.apple.coregraphics.Arrow",
        "com.apple.coregraphics.IBeam",
        "com.apple.cursor.13",          // Pointing Hand
        "com.apple.coregraphics.Wait",
        "com.apple.cursor.4",           // Busy but Clickable
        "com.apple.coregraphics.Move",
        "com.apple.cursor.12",          // Open Hand
        "com.apple.cursor.11",          // Closed Hand
    ]

    public static func name(for identifier: String) -> String {
        all[identifier] ?? "Unknown"
    }

    static func rank(of identifier: String) -> Int {
        prominent.firstIndex(of: identifier) ?? prominent.count
    }
}
