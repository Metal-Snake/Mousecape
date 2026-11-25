import Foundation
import LoginAgentKit
import Observation
import ServiceManagement

/// The background agent (`mousecloak --listen`) that re-applies the cape at login, on user
/// switches and on display changes, as Settings shows it. The job itself, and the user's
/// choice whether it runs, are `LaunchAgent` in LoginAgentKit, shared with
/// `mousecloak --repair-agent`.
@MainActor @Observable
final class LoginAgent {
    /// This app's agent. Outside an app bundle (`swift run`) it still gets one, under the
    /// default identifier, as before.
    private let agent: LaunchAgent = LaunchAgent.current ?? LaunchAgent(
        bundleIdentifier: Bundle.main.bundleIdentifier ?? LaunchAgent.defaultBundleIdentifier,
        appURL: Bundle.main.bundleURL,
        build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")

    private(set) var isEnabled = false
    /// Turned on, but launchd isn't running it (e.g. switched off under System Settings →
    /// General → Login Items & Extensions).
    private(set) var needsApproval = false
    private(set) var lastError: String?

    init() {
        refresh()
    }

    var logURL: URL { agent.logURL }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        agent.setEnabledPreference(enabled)
        do {
            if enabled {
                try agent.install()
            } else {
                try agent.uninstall()
            }
        } catch {
            NSLog("Mousecape agent: %@", "\(error)")
            lastError = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        isEnabled = agent.isEnabled
        needsApproval = isEnabled && !agent.isLoaded
    }

    /// At launch: puts the agent back if it should run but its plist is gone (Homebrew
    /// removes it on every upgrade), and keeps the plist pointing at this copy and build of
    /// the app (it may have moved or been updated) and loaded.
    func repairIfNeeded() {
        do {
            try agent.repairIfNeeded()
        } catch {
            NSLog("Mousecape agent: %@", "\(error)")
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
