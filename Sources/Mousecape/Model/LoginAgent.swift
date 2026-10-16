import Foundation
import Observation
import ServiceManagement

/// The background agent (`mousecloak --listen`) that re-applies the cape at login, on user
/// switches and on display changes. Registered as a launch agent through SMAppService;
/// the plist lives in Contents/Library/LaunchAgents of the app bundle.
@MainActor @Observable
final class LoginAgent {
    static let plistName = "io.github.metal-snake.Mousecape.agent.plist"

    private let service = SMAppService.agent(plistName: plistName)
    private(set) var status: SMAppService.Status
    private(set) var lastError: String?

    init() {
        status = service.status
    }

    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        status = service.status
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
