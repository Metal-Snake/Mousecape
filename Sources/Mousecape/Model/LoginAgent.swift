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
    /// This app's agent. Nil outside an app bundle (`swift run`): such a build has no
    /// `mousecloak` to copy, and must not touch the installed app's agent or choice.
    private let agent: LaunchAgent? = LaunchAgent.current

    private(set) var isEnabled = false
    /// Turned on, but launchd isn't running it (e.g. switched off under System Settings →
    /// General → Login Items & Extensions).
    private(set) var needsApproval = false
    private(set) var lastError: String?

    init() {
        refresh()
    }

    /// The choice is stored only once it took effect, so a failed install doesn't leave the
    /// switch on. When only loading failed (launchd refuses it until approved in Login
    /// Items), the plist and copy are in place, so the agent counts as on and needing approval.
    func setEnabled(_ enabled: Bool) {
        lastError = nil
        guard let agent else {
            lastError = String(localized: "The background agent works only in Mousecape.app, not in this build.")
            return
        }
        do {
            if enabled {
                try agent.install()
            } else {
                try agent.uninstall()
            }
            agent.setEnabledPreference(enabled)
        } catch LaunchAgent.AgentError.launchctl(let output) where enabled {
            agent.setEnabledPreference(true)
            NSLog("Mousecape agent: %@", output)
            lastError = LaunchAgent.AgentError.launchctl(output).localizedDescription
        } catch {
            NSLog("Mousecape agent: %@", "\(error)")
            lastError = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        guard let agent else {
            isEnabled = false
            needsApproval = false
            return
        }
        isEnabled = agent.isEnabled
        needsApproval = isEnabled && !agent.isLoaded
    }

    /// At launch: puts the agent back if it should run but its plist is gone (Homebrew
    /// removes it on every upgrade), and keeps the plist pointing at this copy and build of
    /// the app (it may have moved or been updated) and loaded.
    func repairIfNeeded() {
        guard let agent else { return }
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
