import Foundation
import Observation
import C5hCore
import C5hStore

@Observable
@MainActor
final class ProvidersViewModel {
    var configuredPaths: [ProviderID: String] = [:]
    var wakePrompts: [ProviderID: String] = [:]
    var usageRefreshIntervals: [ProviderID: Int] = [:]
    var checkWhenIdle: [ProviderID: Bool] = [:]
    var usageChecks: [ProviderID: ProviderUsageCheck] = [:]
    var loadingUsageProviders: Set<ProviderID> = []
    var lastError: String?

    private let registry: ProviderRegistry
    private let appSettings: any AppSettingsRepository
    private let usageSnapshotRepository: any UsageSnapshotRepository
    private let fetcher: UsageFetcher
    private let refreshProviderStatus: @MainActor (ProviderID) async -> Void

    init(
        registry: ProviderRegistry,
        appSettings: any AppSettingsRepository,
        usageSnapshotRepository: any UsageSnapshotRepository,
        actual5hRepository: any ActualWindow5hRepository,
        actual7dRepository: any ActualWindow7dRepository,
        refreshProviderStatus: @escaping @MainActor (ProviderID) async -> Void
    ) {
        self.registry = registry
        self.appSettings = appSettings
        self.usageSnapshotRepository = usageSnapshotRepository
        self.refreshProviderStatus = refreshProviderStatus
        self.fetcher = UsageFetcher(
            persistSnapshot: { snapshot in
                try await usageSnapshotRepository.create(snapshot)
            },
            upsertActualWindow5h: { window, tolerance in
                try await actual5hRepository.upsertByEndAt(window, tolerance: tolerance)
            },
            upsertActualWindow7d: { window, tolerance in
                try await actual7dRepository.upsertByEndAt(window, tolerance: tolerance)
            }
        )
    }

    func bootstrap() async {
        for id in ProviderID.allCases {
            await loadConfiguredPath(for: id)
            await loadWakePrompt(for: id)
            await loadUsageRefreshInterval(for: id)
            await loadCheckWhenIdle(for: id)
            await loadLatestUsageCheck(for: id)
        }
    }

    private func loadUsageRefreshInterval(for id: ProviderID) async {
        let key = AppSettingsKeys.usageRefreshIntervalSeconds(for: id)
        let stored = (try? await appSettings.get(key, as: Int.self)) ?? nil
        usageRefreshIntervals[id] = stored ?? AppSettingsKeys.defaultUsageRefreshIntervalSeconds
    }

    func setUsageRefreshInterval(id: ProviderID, _ seconds: Int) async {
        let key = AppSettingsKeys.usageRefreshIntervalSeconds(for: id)
        do {
            try await appSettings.set(key, value: seconds)
            usageRefreshIntervals[id] = seconds
        } catch {
            lastError = String(describing: error)
        }
    }

    private func loadCheckWhenIdle(for id: ProviderID) async {
        let key = AppSettingsKeys.checkUsageWhenIdle(for: id)
        let stored = (try? await appSettings.get(key, as: Bool.self)) ?? nil
        checkWhenIdle[id] = stored ?? AppSettingsKeys.defaultCheckUsageWhenIdle
    }

    func setCheckWhenIdle(id: ProviderID, _ enabled: Bool) async {
        let key = AppSettingsKeys.checkUsageWhenIdle(for: id)
        do {
            try await appSettings.set(key, value: enabled)
            checkWhenIdle[id] = enabled
        } catch {
            lastError = String(describing: error)
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
            await refreshProviderStatus(id)
        } catch {
            lastError = String(describing: error)
        }
    }

    func runUsage(id: ProviderID) async {
        loadingUsageProviders.insert(id)
        defer { loadingUsageProviders.remove(id) }

        do {
            let adapter = try registry.adapter(for: id)
            let snapshot = try await fetcher.fetchAndPersist(adapter: adapter)
            usageChecks[id] = Self.usageCheck(from: snapshot)
            lastError = nil
        } catch {
            if (error as? C5hError)?.isUsageRefreshAlreadyRunning == true {
                await loadLatestUsageCheck(for: id)
                lastError = nil
                return
            }
            let message = String(describing: error)
            usageChecks[id] = ProviderUsageCheck(
                checkedAt: .now,
                usedPercentage: nil,
                windowEndsAt: nil,
                errorMessage: message
            )
            lastError = message
        }
    }

    private func loadLatestUsageCheck(for id: ProviderID) async {
        do {
            if let snapshot = try await usageSnapshotRepository.fetchLatest(providerID: id) {
                usageChecks[id] = Self.usageCheck(from: snapshot)
            }
        } catch {
            usageChecks[id] = ProviderUsageCheck(
                checkedAt: .now,
                usedPercentage: nil,
                windowEndsAt: nil,
                errorMessage: String(describing: error)
            )
        }
    }

    private static func usageCheck(from snapshot: UsageSnapshot) -> ProviderUsageCheck {
        let normalized = normalizedUsage(from: snapshot)
        return ProviderUsageCheck(
            checkedAt: snapshot.capturedAt,
            usedPercentage: normalized?.usedPercentage,
            windowEndsAt: normalized?.windowEndsAt,
            errorMessage: nil
        )
    }

    private static func normalizedUsage(from snapshot: UsageSnapshot) -> NormalizedUsage? {
        guard let data = snapshot.normalizedJSON.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(NormalizedUsage.self, from: data)
    }
}

struct ProviderUsageCheck: Sendable, Hashable {
    var checkedAt: Date
    var usedPercentage: Double?
    var windowEndsAt: Date?
    var errorMessage: String?
}
