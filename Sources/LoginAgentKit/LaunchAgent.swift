import AppKit

/// The background agent (`mousecloak --listen`) as a launchd job: a plain launch agent in
/// ~/Library/LaunchAgents that runs a copy of the app's `mousecloak`. Shared by the app
/// (Settings, and a repair at launch) and by `mousecloak --repair-agent`, which Homebrew's
/// cask runs after installing.
///
/// The copy lives outside the app (`agentDirectory`), because the Finder refuses to move or
/// delete an app while a process from its bundle runs. The app refreshes the copy at every
/// launch; the agent removes itself once no copy of the app is left (`appIsGone`).
///
/// Whether the agent should run is the user's choice, kept in the preferences
/// (`enabledKey`), not read from the plist: Homebrew's cask removes the plist on every
/// upgrade, not only on uninstall, and the choice has to survive that.
///
/// Not SMAppService: that pins the agent to the exact build of an app without an Apple
/// team ID (ad-hoc or self-signed), so after every update launchd refused to start it
/// ("needs LWCR update"). A plain agent isn't pinned, so updates just work.
public struct LaunchAgent: Sendable {
    /// The app's bundle identifier; the label and the preferences domain follow from it, so
    /// a test copy under another identifier has an agent and a choice of its own.
    public let bundleIdentifier: String
    /// The app bundle whose `mousecloak` the agent runs.
    public let appURL: URL
    /// The app's build number. The plist carries it (as an environment variable, which
    /// launchd accepts and the agent ignores), so an update at the same path is noticed:
    /// the running agent would otherwise keep the old code until the next login.
    public let build: String
    public let home: URL

    public static let defaultBundleIdentifier = "io.github.metal-snake.Mousecape"
    /// In the app's own preferences domain (its bundle identifier).
    public static let enabledKey = "MCLoginAgentEnabled"
    static let buildVariable = "MOUSECAPE_BUILD"
    /// The app's bundle identifier and path, for the agent's check whether the app is gone.
    public static let appIdentifierVariable = "MOUSECAPE_APP"
    public static let appPathVariable = "MOUSECAPE_APP_PATH"

    public init(bundleIdentifier: String, appURL: URL, build: String,
                home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.bundleIdentifier = bundleIdentifier
        self.appURL = appURL
        self.build = build
        self.home = home
    }

    /// The agent of the app this code runs in. For `mousecloak` inside the app bundle,
    /// `Bundle.main` is the app too. Nil outside an app bundle (e.g. a `swift build`
    /// product), where there is no app for the agent to run from.
    public static var current: LaunchAgent? {
        let bundle = Bundle.main
        guard bundle.bundleURL.pathExtension == "app" else { return nil }
        return LaunchAgent(bundleIdentifier: bundle.bundleIdentifier ?? defaultBundleIdentifier,
                           appURL: bundle.bundleURL,
                           build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
    }

    public var label: String { "\(bundleIdentifier).listener" }

    public var plistURL: URL { home.appending(path: "Library/LaunchAgents/\(label).plist") }

    public var logURL: URL { home.appending(path: "Library/Logs/Mousecape/agent.log") }

    /// The app's own `mousecloak`, which the agent's copy is made from.
    public var bundledExecutable: URL { appURL.appending(path: "Contents/MacOS/mousecloak") }

    /// Where the agent's copy of `mousecloak` lives, per bundle identifier.
    public var agentDirectory: URL {
        home.appending(path: "Library/Application Support/Mousecape/Agent/\(bundleIdentifier)", directoryHint: .isDirectory)
    }

    /// The program the agent runs: the copy.
    public var executable: URL { agentDirectory.appending(path: "mousecloak") }

    /// The job as written to `plistURL`.
    public var plist: [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [executable.path, "--listen"],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
            "StandardOutPath": logURL.path,
            "StandardErrorPath": logURL.path,
            "AssociatedBundleIdentifiers": [bundleIdentifier],
            "EnvironmentVariables": [Self.buildVariable: build,
                                     Self.appIdentifierVariable: bundleIdentifier,
                                     Self.appPathVariable: appURL.path],
        ]
    }

    // MARK: - The user's choice

    /// Whether the user wants the agent. Before the choice was kept in the preferences,
    /// the plist alone said so, so without a stored choice an existing plist counts as on.
    public var isEnabled: Bool {
        if let stored = CFPreferencesCopyAppValue(Self.enabledKey as CFString, bundleIdentifier as CFString) as? Bool {
            return stored
        }
        return FileManager.default.fileExists(atPath: plistURL.path)
    }

    public func setEnabledPreference(_ enabled: Bool) {
        CFPreferencesSetAppValue(Self.enabledKey as CFString, enabled as CFBoolean, bundleIdentifier as CFString)
        CFPreferencesAppSynchronize(bundleIdentifier as CFString)
    }

    // MARK: - The job

    /// The program path and the app build in the installed plist, if there is one. A plist
    /// written before builds were recorded has no build, so it counts as outdated.
    public var installed: InstalledAgent? {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        let environment = plist["EnvironmentVariables"] as? [String: String]
        return InstalledAgent(program: (plist["ProgramArguments"] as? [String])?.first,
                              build: environment?[Self.buildVariable],
                              appPath: environment?[Self.appPathVariable])
    }

    public var isLoaded: Bool {
        Self.launchctl(["print", "gui/\(getuid())/\(label)"]).status == 0
    }

    /// Whether the agent has to be (re)installed: it should run, and its plist is missing or
    /// points at another program, build or place of the app, its copy of `mousecloak` is
    /// missing, or it isn't loaded.
    public static func needsInstall(enabled: Bool, installed: InstalledAgent?, executable: String, build: String,
                                    appPath: String, copyExists: Bool, loaded: Bool) -> Bool {
        guard enabled else { return false }
        guard let installed else { return true }
        return installed.program != executable || installed.build != build || installed.appPath != appPath
            || !copyExists || !loaded
    }

    /// Puts the agent back the way the user chose it: at app launch, and after Homebrew
    /// installed or upgraded the app. Installing again restarts the agent with this build.
    /// Returns whether it installed.
    @discardableResult
    public func repairIfNeeded() throws -> Bool {
        let enabled = isEnabled
        setEnabledPreference(enabled)                   // records a choice that came from the plist
        guard Self.needsInstall(enabled: enabled, installed: installed, executable: executable.path, build: build,
                                appPath: appURL.path,
                                copyExists: FileManager.default.isExecutableFile(atPath: executable.path),
                                loaded: isLoaded) else { return false }
        try install()
        return true
    }

    /// Copies `mousecloak` out of the app, writes the plist and (re)loads it, so a new build
    /// or place of the app takes effect now and not only at the next login.
    public func install() throws {
        let files = FileManager.default
        try files.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try copyExecutable()
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
        Self.launchctl(["bootout", "gui/\(getuid())/\(label)"])
        let result = Self.launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
        if result.status != 0 && !isLoaded {
            throw AgentError.launchctl(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func uninstall() throws {
        Self.launchctl(["bootout", "gui/\(getuid())/\(label)"])
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
        if FileManager.default.fileExists(atPath: agentDirectory.path) {
            try FileManager.default.removeItem(at: agentDirectory)
        }
    }

    /// Replaces the copy in one step, so a running agent keeps its old file until it
    /// restarts. The copy keeps the code signature; a quarantine flag the app may carry
    /// is removed, so macOS doesn't stop launchd from running it.
    private func copyExecutable() throws {
        let files = FileManager.default
        try files.createDirectory(at: agentDirectory, withIntermediateDirectories: true)
        let fresh = agentDirectory.appending(path: ".mousecloak-\(UUID().uuidString)")
        try files.copyItem(at: bundledExecutable, to: fresh)
        removexattr(fresh.path, "com.apple.quarantine", 0)
        if files.fileExists(atPath: executable.path) {
            _ = try files.replaceItemAt(executable, withItemAt: fresh)
        } else {
            try files.moveItem(at: fresh, to: executable)
        }
    }

    // MARK: - The agent's side

    /// Whether no copy of the app is left: none at `recordedPath`, and none that Launch
    /// Services knows outside the Trash. The agent asks this at start; a moved app is still
    /// found, and the app updates the path when it next opens.
    public static func appIsGone(bundleIdentifier: String, recordedPath: String?) -> Bool {
        if let recordedPath, FileManager.default.fileExists(atPath: recordedPath),
           !recordedPath.contains("/.Trash/") {
            return false
        }
        let apps = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleIdentifier)
        return !apps.contains { !$0.path.contains("/.Trash/") && FileManager.default.fileExists(atPath: $0.path) }
    }

    /// For the agent once its app is gone: removes its plist and its copy of `mousecloak`,
    /// then unloads itself, which ends this process. The cape stays until logout.
    public func removeItself() {
        try? FileManager.default.removeItem(at: plistURL)
        try? FileManager.default.removeItem(at: agentDirectory)
        Self.launchctl(["bootout", "gui/\(getuid())/\(label)"])
    }

    @discardableResult
    static func launchctl(_ arguments: [String]) -> (status: Int32, output: String) {
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

    public enum AgentError: LocalizedError {
        case launchctl(String)

        public var errorDescription: String? {
            switch self {
            case .launchctl(let output):
                String(localized: "The background agent could not be started: \(output)")
            }
        }
    }
}

/// What an installed agent's plist says.
public struct InstalledAgent: Equatable, Sendable {
    public var program: String?
    public var build: String?
    public var appPath: String?

    public init(program: String?, build: String?, appPath: String? = nil) {
        self.program = program
        self.build = build
        self.appPath = appPath
    }
}
