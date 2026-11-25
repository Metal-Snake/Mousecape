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
    #expect(plist["ProgramArguments"] as? [String] == ["/Applications/Mousecape.app/Contents/MacOS/mousecloak", "--listen"])
    #expect((plist["EnvironmentVariables"] as? [String: String])?["MOUSECAPE_BUILD"] == "42")
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
    #expect(test.agent.installed == InstalledAgent(program: test.agent.executable.path, build: "42"))
}

@Test func installsOnlyWhenTurnedOnAndSomethingIsOff() {
    let program = "/Applications/Mousecape.app/Contents/MacOS/mousecloak"
    let current = InstalledAgent(program: program, build: "42")
    func needs(_ enabled: Bool, _ installed: InstalledAgent?, loaded: Bool = true) -> Bool {
        LaunchAgent.needsInstall(enabled: enabled, installed: installed, executable: program, build: "42", loaded: loaded)
    }
    #expect(!needs(false, nil))                                         // turned off: never
    #expect(needs(true, nil))                                           // plist gone (Homebrew upgrade)
    #expect(!needs(true, current))                                      // all fine
    #expect(needs(true, current, loaded: false))                        // not loaded
    #expect(needs(true, InstalledAgent(program: program, build: "41"))) // older build
    #expect(needs(true, InstalledAgent(program: "/old/place/mousecloak", build: "42")))   // app moved
    #expect(needs(true, InstalledAgent(program: program, build: nil)))  // written before builds were recorded
}
