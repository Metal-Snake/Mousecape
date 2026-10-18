import Foundation
import Observation
import Security
import ServiceManagement

/// The background agent (`mousecloak --listen`) that re-applies the cape at login, on user
/// switches and on display changes. Registered as a launch agent through SMAppService;
/// the plist lives in Contents/Library/LaunchAgents of the app bundle.
@MainActor @Observable
final class LoginAgent {
    static let plistName = "io.github.metal-snake.Mousecape.agent.plist"
    /// Code hashes of the app and the agent binary at the last registration.
    private static let registeredHashKey = "agentRegisteredCodeHash"

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
                UserDefaults.standard.set(Self.agentCodeHash(), forKey: Self.registeredHashKey)
            } else {
                try service.unregister()
                UserDefaults.standard.removeObject(forKey: Self.registeredHashKey)
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        status = service.status
    }

    /// An ad-hoc signed agent is pinned to the exact build: after a new build or an update,
    /// launchd refuses to start it ("needs LWCR update", exit 78) until it is registered
    /// again. That requirement covers the app bundle too, not just the agent binary, so
    /// both hashes are compared. Registering once more is not enough; it has to be
    /// unregistered first. Done at launch, and only when the build changed.
    func renewRegistrationIfNeeded() {
        guard service.status == .enabled, let hash = Self.agentCodeHash(),
              UserDefaults.standard.string(forKey: Self.registeredHashKey) != hash else { return }
        do {
            try service.unregister()
            try service.register()
            UserDefaults.standard.set(hash, forKey: Self.registeredHashKey)
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// The code directory hashes of the app bundle and of Contents/MacOS/mousecloak, as hex.
    private static func agentCodeHash() -> String? {
        guard let app = codeHash(of: Bundle.main.bundleURL),
              let agent = codeHash(of: Bundle.main.bundleURL.appending(path: "Contents/MacOS/mousecloak")) else { return nil }
        return app + "+" + agent
    }

    private static func codeHash(of url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(), &info) == errSecSuccess,
              let hash = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data else { return nil }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
