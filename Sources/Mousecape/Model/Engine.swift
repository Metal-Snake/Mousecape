import Foundation
import MousecloakCore

/// Swift face of the Objective-C cursor engine. Everything here acts on the live system
/// cursors of the current login session.
@MainActor
enum Engine {
    /// Applies the cape file; the engine backs up the system cursors first and records the
    /// cape as applied, so the background agent can re-apply it later.
    static func apply(_ url: URL) -> Bool {
        applyCapeAtPath(url.path)
    }

    /// Back to the macOS cursors.
    static func reset() {
        resetAllCursors()
    }

    static var scale: Float {
        get { cursorScale() }
        set { _ = setCursorScale(newValue) }
    }

    /// Writes the cursors currently on screen into a new cape file.
    static func dumpCurrentCursors(to url: URL) -> Bool {
        dumpCursorsToFile(url.path) { _, _ in true }
    }

    /// Converts a MightyMouse theme into a cape property list.
    static func convertMightyMouse(at url: URL) -> [String: Any]? {
        guard let mightyMouse = NSDictionary(contentsOf: url) as? [AnyHashable: Any] else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        let metadata: [AnyHashable: Any] = [
            "name": name,
            "version": 1.0,
            "author": String(localized: "Unknown"),
            "identifier": "local.import.\(name).\(Int(Date().timeIntervalSinceReferenceDate))",
        ]
        return createCapeFromMightyMouse(mightyMouse, metadata) as? [String: Any]
    }
}

/// The preferences shared with the engine and the background agent. They live in the
/// original Mousecape domain, so an existing library and settings carry over.
enum EnginePreferences {
    static let domain = "com.alexzielenski.Mousecape"
    static var defaults: UserDefaults { UserDefaults(suiteName: domain)! }

    /// Identifier of the applied cape. The engine writes it per host, which plain
    /// UserDefaults does not read, hence CFPreferences.
    static var appliedCapeIdentifier: String? {
        CFPreferencesAppSynchronize(domain as CFString)
        return CFPreferencesCopyAppValue("MCAppliedCursor" as CFString, domain as CFString) as? String
    }

    /// Cursor scale the agent restores at login and on display changes. Nil until the
    /// user picks one; the agent then leaves the system's scale alone.
    static var cursorScale: Float? {
        get { (defaults.object(forKey: "MCCursorScale") as? NSNumber)?.floatValue }
        set { defaults.set(newValue, forKey: "MCCursorScale") }
    }

    /// Mirrors pointer cursors horizontally, for left-handed use.
    static var leftHanded: Bool {
        get { defaults.bool(forKey: "MCHandedness") }
        set { defaults.set(newValue, forKey: "MCHandedness") }
    }
}
