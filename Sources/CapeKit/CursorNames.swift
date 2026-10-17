/// Human-readable names of the system cursor identifiers (mirrors `cursorMap()` in the engine).
public enum CursorNames {
    public static let all: [String: String] = [
        "com.apple.coregraphics.Arrow": "Arrow",
        "com.apple.coregraphics.IBeam": "IBeam",
        "com.apple.coregraphics.IBeamXOR": "IBeamXOR",
        "com.apple.coregraphics.Alias": "Alias",
        "com.apple.coregraphics.Copy": "Copy",
        "com.apple.coregraphics.Move": "Move",
        "com.apple.coregraphics.ArrowCtx": "Ctx Arrow",
        "com.apple.coregraphics.ArrowS": "Arrow S",
        "com.apple.coregraphics.IBeamS": "IBeam S",
        "com.apple.coregraphics.Wait": "Wait",
        "com.apple.coregraphics.Empty": "Empty",
        "com.apple.cursor.2": "Link",
        "com.apple.cursor.3": "Forbidden",
        "com.apple.cursor.4": "Busy",
        "com.apple.cursor.5": "Copy Drag",
        "com.apple.cursor.7": "Crosshair",
        "com.apple.cursor.8": "Crosshair 2",
        "com.apple.cursor.9": "Camera 2",
        "com.apple.cursor.10": "Camera",
        "com.apple.cursor.11": "Closed",
        "com.apple.cursor.12": "Open",
        "com.apple.cursor.13": "Pointing",
        "com.apple.cursor.14": "Counting Up",
        "com.apple.cursor.15": "Counting Down",
        "com.apple.cursor.16": "Counting Up/Down",
        "com.apple.cursor.17": "Resize W",
        "com.apple.cursor.18": "Resize E",
        "com.apple.cursor.19": "Resize W-E",
        "com.apple.cursor.20": "Cell XOR",
        "com.apple.cursor.21": "Resize N",
        "com.apple.cursor.22": "Resize S",
        "com.apple.cursor.23": "Resize N-S",
        "com.apple.cursor.24": "Ctx Menu",
        "com.apple.cursor.25": "Poof",
        "com.apple.cursor.26": "IBeam H.",
        "com.apple.cursor.27": "Window E",
        "com.apple.cursor.28": "Window E-W",
        "com.apple.cursor.29": "Window NE",
        "com.apple.cursor.30": "Window NE-SW",
        "com.apple.cursor.31": "Window N",
        "com.apple.cursor.32": "Window N-S",
        "com.apple.cursor.33": "Window NW",
        "com.apple.cursor.34": "Window NW-SE",
        "com.apple.cursor.35": "Window SE",
        "com.apple.cursor.36": "Window S",
        "com.apple.cursor.37": "Window SW",
        "com.apple.cursor.38": "Window W",
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
        "com.apple.cursor.13",          // Pointing
        "com.apple.coregraphics.Wait",
        "com.apple.cursor.4",           // Busy
        "com.apple.coregraphics.Move",
        "com.apple.cursor.12",          // Open
        "com.apple.cursor.11",          // Closed
    ]

    public static func name(for identifier: String) -> String {
        all[identifier] ?? "Unknown"
    }

    static func rank(of identifier: String) -> Int {
        prominent.firstIndex(of: identifier) ?? prominent.count
    }
}
