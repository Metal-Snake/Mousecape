import Foundation
import Testing
import LoginAgentKit

/// An agent under a made-up identifier and a temporary home, so the tests touch neither the
/// real agent nor its choice. `remove()` clears the preference again.
private struct TestAgent {
    let agent: LaunchAgent
    let home: URL

    init() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "launch-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        agent = LaunchAgent(bundleIdentifier: "test.mousecape.agent.\(UUID().uuidString)",
                            appURL: URL(fileURLWithPath: "/Applications/Mousecape.app"), build: "42", home: home)
    }

    func remove() {
        CFPreferencesSetAppValue(LaunchAgent.enabledKey as CFString, nil, agent.bundleIdentifier as CFString)
        CFPreferencesAppSynchronize(agent.bundleIdentifier as CFString)
        try? FileManager.default.removeItem(at: home)
    }
}

@Test func plistRunsTheAppsMousecloak() throws {
    let test = try TestAgent()
    defer { test.remove() }
    let plist = test.agent.plist
    #expect(plist["Label"] as? String == "\(test.agent.bundleIdentifier).listener")
    // A copy outside the app, so the Finder can move the app while the agent runs.
    #expect(plist["ProgramArguments"] as? [String] == [test.agent.executable.path, "--listen"])
    #expect(test.agent.executable.path.hasPrefix(test.home.path + "/Library/Application Support/Mousecape/Agent/"))
    #expect(!test.agent.executable.path.contains(".app/"))
    let environment = plist["EnvironmentVariables"] as? [String: String]
    #expect(environment?["MOUSECAPE_BUILD"] == "42")
    #expect(environment?["MOUSECAPE_APP"] == test.agent.bundleIdentifier)
    #expect(environment?["MOUSECAPE_APP_PATH"] == "/Applications/Mousecape.app")
    #expect(test.agent.plistURL.path.hasSuffix("Library/LaunchAgents/\(test.agent.bundleIdentifier).listener.plist"))
}

/// Without a stored choice the plist says it (how earlier versions kept it); once stored,
/// the choice wins, also when Homebrew has removed the plist.
@Test func choiceSurvivesAMissingPlist() throws {
    let test = try TestAgent()
    defer { test.remove() }
    #expect(!test.agent.isEnabled)

    try FileManager.default.createDirectory(at: test.agent.plistURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try Data("<plist/>".utf8).write(to: test.agent.plistURL)
    #expect(test.agent.isEnabled)

    test.agent.setEnabledPreference(true)
    try FileManager.default.removeItem(at: test.agent.plistURL)
    #expect(test.agent.isEnabled)

    test.agent.setEnabledPreference(false)
    #expect(!test.agent.isEnabled)
}

@Test func readsTheInstalledPlist() throws {
    let test = try TestAgent()
    defer { test.remove() }
    #expect(test.agent.installed == nil)
    try FileManager.default.createDirectory(at: test.agent.plistURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(fromPropertyList: test.agent.plist, format: .xml, options: 0)
    try data.write(to: test.agent.plistURL)
    #expect(test.agent.installed == InstalledAgent(program: test.agent.executable.path, build: "42",
                                                   appPath: "/Applications/Mousecape.app"))
}

@Test func installsOnlyWhenTurnedOnAndSomethingIsOff() {
    let program = "/Users/me/Library/Application Support/Mousecape/Agent/x/mousecloak"
    let app = "/Applications/Mousecape.app"
    let current = InstalledAgent(program: program, build: "42", appPath: app)
    func needs(_ enabled: Bool, _ installed: InstalledAgent?, copy: Bool = true, loaded: Bool = true) -> Bool {
        LaunchAgent.needsInstall(enabled: enabled, installed: installed, executable: program, build: "42",
                                 appPath: app, copyExists: copy, loaded: loaded)
    }
    #expect(!needs(false, nil))                                         // turned off: never
    #expect(needs(true, nil))                                           // plist gone (Homebrew upgrade)
    #expect(!needs(true, current))                                      // all fine
    #expect(needs(true, current, loaded: false))                        // not loaded
    #expect(needs(true, current, copy: false))                          // copy gone
    #expect(needs(true, InstalledAgent(program: program, build: "41", appPath: app)))     // older build
    #expect(needs(true, InstalledAgent(program: program, build: "42", appPath: "/Old/Mousecape.app")))  // app moved
    #expect(needs(true, InstalledAgent(program: "\(app)/Contents/MacOS/mousecloak", build: "42")))  // ran from the app
}

@Test func appIsGoneOnlyWithoutAnyCopy() throws {
    let test = try TestAgent()
    defer { test.remove() }
    let unknown = "test.mousecape.missing.\(UUID().uuidString)"
    #expect(LaunchAgent.appIsGone(bundleIdentifier: unknown, recordedPath: nil))
    #expect(LaunchAgent.appIsGone(bundleIdentifier: unknown, recordedPath: "/nowhere/Mousecape.app"))
    // Still at its recorded place.
    #expect(!LaunchAgent.appIsGone(bundleIdentifier: unknown, recordedPath: test.home.path))
    // In the Trash counts as gone.
    let trashed = test.home.appending(path: ".Trash/Mousecape.app")
    try FileManager.default.createDirectory(at: trashed, withIntermediateDirectories: true)
    #expect(LaunchAgent.appIsGone(bundleIdentifier: unknown, recordedPath: trashed.path))
}
