import Foundation
import Observation
import C5hCore
import C5hStore

@Observable
@MainActor
final class ProvidersViewModel {
    var statuses: [ProviderID: ProviderStatus] = [:]
    var loadingProviders: Set<ProviderID> = []
    var configuredPaths: [ProviderID: String] = [:]
    var wakePrompts: [ProviderID: String] = [:]
    var lastError: String?

    private let registry: ProviderRegistry
    private let appSettings: any AppSettingsRepository

    init(registry: ProviderRegistry, appSettings: any AppSettingsRepository) {
        self.registry = registry
        self.appSettings = appSettings
    }

    func bootstrap() async {
        for id in ProviderID.allCases {
            await loadConfiguredPath(for: id)
            await loadWakePrompt(for: id)
            await refreshProvider(id: id)
        }
    }

    private func loadConfiguredPath(for id: ProviderID) async {
        let key = "providers.\(id.rawValue).cliPath"
        do {
            if let path = try await appSettings.get(key, as: String.self) {
                configuredPaths[id] = path
            } else {
                configuredPaths[id] = ""
            }
        } catch {
            configuredPaths[id] = ""
        }
    }

    private func loadWakePrompt(for id: ProviderID) async {
        let key = AppSettingsKeys.defaultWakePrompt(for: id)
        let value = (try? await appSettings.get(key, as: String.self)) ?? nil
        wakePrompts[id] = value ?? ""
    }

    func refreshProvider(id: ProviderID) async {
        loadingProviders.insert(id)
        defer { loadingProviders.remove(id) }

        let versionStatus = await runVersion(id: id, managesLoading: false)
        guard versionStatus.isInstalled, versionStatus.errorMessage == nil else { return }
        await runAuthStatus(id: id, managesLoading: false)
    }

    @discardableResult
    func runVersion(id: ProviderID, managesLoading: Bool = true) async -> ProviderStatus {
        if managesLoading { loadingProviders.insert(id) }
        defer { if managesLoading { loadingProviders.remove(id) } }
        do {
            let adapter = try registry.adapter(for: id)
            var status = await adapter.runVersionCommand()
            if status.isInstalled {
                status.isAuthenticated = statuses[id]?.isAuthenticated
            }
            statuses[id] = status
            lastError = nil
            return status
        } catch {
            lastError = String(describing: error)
            let status = ProviderStatus(providerID: id, isInstalled: false, errorMessage: lastError)
            statuses[id] = status
            return status
        }
    }

    @discardableResult
    func runAuthStatus(id: ProviderID, managesLoading: Bool = true) async -> ProviderStatus {
        if managesLoading { loadingProviders.insert(id) }
        defer { if managesLoading { loadingProviders.remove(id) } }
        do {
            let adapter = try registry.adapter(for: id)
            let authStatus = await adapter.runAuthStatusCommand()
            let existing = statuses[id]
            let status = ProviderStatus(
                providerID: id,
                isInstalled: existing?.isInstalled ?? authStatus.isInstalled,
                cliPath: authStatus.cliPath ?? existing?.cliPath,
                version: existing?.version,
                isAuthenticated: authStatus.isAuthenticated,
                lastCheckedAt: authStatus.lastCheckedAt,
                errorMessage: authStatus.errorMessage
            )
            statuses[id] = status
            lastError = nil
            return status
        } catch {
            lastError = String(describing: error)
            let status = ProviderStatus(
                providerID: id,
                isInstalled: statuses[id]?.isInstalled ?? false,
                cliPath: statuses[id]?.cliPath,
                version: statuses[id]?.version,
                isAuthenticated: statuses[id]?.isAuthenticated,
                errorMessage: lastError
            )
            statuses[id] = status
            return status
        }
    }

    func setWakePrompt(id: ProviderID, _ value: String) async {
        let key = AppSettingsKeys.defaultWakePrompt(for: id)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try await appSettings.remove(key)
                wakePrompts[id] = ""
            } else {
                try await appSettings.set(key, value: trimmed)
                wakePrompts[id] = trimmed
            }
        } catch {
            lastError = String(describing: error)
        }
    }

    func setCLIPath(id: ProviderID, _ path: String?) async {
        let key = "providers.\(id.rawValue).cliPath"
        do {
            if let path, !path.isEmpty {
                try await appSettings.set(key, value: path)
                configuredPaths[id] = path
            } else {
                try await appSettings.remove(key)
                configuredPaths[id] = ""
            }
            await refreshProvider(id: id)
        } catch {
            lastError = String(describing: error)
        }
    }
}
