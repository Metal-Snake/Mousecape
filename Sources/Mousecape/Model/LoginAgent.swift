import Foundation
import Observation
import ServiceManagement

/// The background agent (`mousecloak --listen`) that re-applies the cape at login, on user
/// switches and on display changes.
///
/// It is a plain launch agent in ~/Library/LaunchAgents that runs `mousecloak` from the app
/// bundle. An agent registered through SMAppService gets pinned to the exact build of an app
/// without an Apple team ID (ad-hoc or self-signed): after every update launchd refused to
/// start it ("needs LWCR update"), and re-registering didn't help. A plain agent isn't
/// pinned, so updates just work.
@MainActor @Observable
final class LoginAgent {
    nonisolated static let label = "io.github.metal-snake.Mousecape.listener"
    /// SMAppService agents of earlier versions, unregistered when found. Their plists stay
    /// in the app bundle because SMAppService can only unregister with the plist present.
    private static let smAppServicePlists = [
        "io.github.metal-snake.Mousecape.agent.plist",
        "io.github.metal-snake.Mousecape.cursor-agent.plist",
    ]
    private static let legacyKeys = ["agentRegisteredCodeHash", "agentEnabled"]

    private(set) var isEnabled = false
    /// Turned on, but launchd isn't running it (e.g. switched off under System Settings →
    /// General → Login Items & Extensions).
    private(set) var needsApproval = false
    private(set) var lastError: String?

    init() {
        refresh()
    }

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/\(label).plist")
    }

    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Mousecape/agent.log")
    }

    private static var agentExecutable: URL {
        Bundle.main.bundleURL.appending(path: "Contents/MacOS/mousecloak")
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try install()
            } else {
                try uninstall()
            }
        } catch {
            NSLog("Mousecape agent: %@", "\(error)")
            lastError = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        isEnabled = FileManager.default.fileExists(atPath: Self.plistURL.path)
        needsApproval = isEnabled && !Self.isLoaded()
    }

    /// At launch: moves an agent of an earlier version over, and keeps the plist pointing at
    /// this copy of the app (it may have moved) and loaded.
    func repairIfNeeded() {
        let defaults = UserDefaults.standard
        var wanted = FileManager.default.fileExists(atPath: Self.plistURL.path)
            || defaults.bool(forKey: "agentEnabled")
            || defaults.string(forKey: "agentRegisteredCodeHash") != nil
        for name in Self.smAppServicePlists {
            let old = SMAppService.agent(plistName: name)
            if old.status == .enabled || old.status == .requiresApproval {
                wanted = true
            }
            if old.status != .notRegistered {
                try? old.unregister()
            }
        }
        Self.legacyKeys.forEach { defaults.removeObject(forKey: $0) }
        guard wanted else { return }
        do {
            if Self.installedProgram() != Self.agentExecutable.path || !Self.isLoaded() {
                try install()
            }
        } catch {
            NSLog("Mousecape agent: %@", "\(error)")
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Private

    private func install() throws {
        try FileManager.default.createDirectory(at: Self.plistURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: Self.logURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [Self.agentExecutable.path, "--listen"],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
            "StandardOutPath": Self.logURL.path,
            "StandardErrorPath": Self.logURL.path,
            "AssociatedBundleIdentifiers": [Bundle.main.bundleIdentifier ?? "io.github.metal-snake.Mousecape"],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: Self.plistURL, options: .atomic)
        // Reload, so a changed program path takes effect now and not only at the next login.
        Self.launchctl(["bootout", "gui/\(getuid())/\(Self.label)"])
        let result = Self.launchctl(["bootstrap", "gui/\(getuid())", Self.plistURL.path])
        if result.status != 0 && !Self.isLoaded() {
            throw AgentError.launchctl(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func uninstall() throws {
        Self.launchctl(["bootout", "gui/\(getuid())/\(Self.label)"])
        if FileManager.default.fileExists(atPath: Self.plistURL.path) {
            try FileManager.default.removeItem(at: Self.plistURL)
        }
    }

    private static func isLoaded() -> Bool {
        launchctl(["print", "gui/\(getuid())/\(label)"]).status == 0
    }

    /// The program path in the installed plist, if there is one.
    private static func installedProgram() -> String? {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String] else { return nil }
        return arguments.first
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else { return (-1, "") }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }

    enum AgentError: LocalizedError {
        case launchctl(String)

        var errorDescription: String? {
            switch self {
            case .launchctl(let output):
                String(localized: "The background agent could not be started: \(output)")
            }
        }
    }
}
