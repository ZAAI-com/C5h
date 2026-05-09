import Foundation
import ServiceManagement
import C5hCore

@MainActor
final class HelperRegistrationService {
    enum Status: Sendable, Equatable {
        case unsupported
        case unregistered
        case registered
        case requiresApproval
        case error(String)

        var label: String {
            switch self {
            case .unsupported: "Unsupported (debug build)"
            case .unregistered: "Not registered"
            case .registered: "Registered"
            case .requiresApproval: "Awaiting approval in System Settings"
            case .error(let msg): "Error: \(msg)"
            }
        }
    }

    static let plistName = "com.zaai.c5h.helper.plist"

    private let agent: SMAppService = SMAppService.agent(plistName: HelperRegistrationService.plistName)

    private(set) var status: Status = .unsupported

    init() {
        refresh()
    }

    func refresh() {
        #if DEBUG
        status = .unsupported
        #else
        switch agent.status {
        case .notRegistered:
            status = .unregistered
        case .enabled:
            status = .registered
        case .requiresApproval:
            status = .requiresApproval
        case .notFound:
            status = .error("LaunchAgent plist missing from app bundle")
        @unknown default:
            status = .error("Unknown SMAppService.Status")
        }
        #endif
    }

    func register() async {
        #if DEBUG
        status = .unsupported
        #else
        do {
            try agent.register()
            refresh()
        } catch {
            status = .error(String(describing: error))
        }
        #endif
    }

    func unregister() async {
        #if DEBUG
        status = .unsupported
        #else
        do {
            try await agent.unregister()
            refresh()
        } catch {
            status = .error(String(describing: error))
        }
        #endif
    }
}
