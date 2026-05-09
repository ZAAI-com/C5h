import Foundation
import Observation
import C5hCore
import C5hStore

@Observable
@MainActor
final class ProvidersViewModel {
    var statuses: [ProviderID: ProviderStatus] = [:]
    var loadingProviders: Set<ProviderID> = []
    var lastTestRunID: [ProviderID: UUID] = [:]
    var configuredPaths: [ProviderID: String] = [:]
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
            await detect(id: id)
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

    func detect(id: ProviderID) async {
        loadingProviders.insert(id)
        defer { loadingProviders.remove(id) }
        do {
            let adapter = try registry.adapter(for: id)
            let status = await adapter.detectStatus()
            statuses[id] = status
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    func runTestCommand(id: ProviderID) async {
        loadingProviders.insert(id)
        defer { loadingProviders.remove(id) }
        do {
            let adapter = try registry.adapter(for: id)
            let run = try await adapter.runTestCommand()
            lastTestRunID[id] = run.id
            await detect(id: id)
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
            await detect(id: id)
        } catch {
            lastError = String(describing: error)
        }
    }
}
