import Foundation
import Observation
import C5hCore
import C5hStore

@Observable
@MainActor
final class AppEnvironment {
    enum LoadState: Sendable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var loadState: LoadState = .loading
    private(set) var paths: AppPaths?
    private(set) var database: Database?
    private(set) var providers: [Provider] = []

    private(set) var providerRepository: (any ProviderRepository)?
    private(set) var plannedWindowRepository: (any PlannedWindowRepository)?
    private(set) var actualWindow5hRepository: (any ActualWindow5hRepository)?
    private(set) var actualWindow7dRepository: (any ActualWindow7dRepository)?
    private(set) var scheduledPromptRepository: (any ScheduledPromptRepository)?
    private(set) var commandRunRepository: (any CommandRunRepository)?
    private(set) var usageSnapshotRepository: (any UsageSnapshotRepository)?
    private(set) var promptTemplateRepository: (any PromptTemplateRepository)?
    private(set) var appSettingsRepository: (any AppSettingsRepository)?
    private(set) var helperHeartbeatRepository: (any HelperHeartbeatRepository)?

    private(set) var cliPathResolver: (any CLIPathResolving)?
    private(set) var commandRunner: (any CommandRunning)?
    private(set) var providerRegistry: ProviderRegistry?
    private(set) var schedulerTicker: SchedulerTicker?
    private(set) var providerStatuses: [ProviderID: ProviderStatus] = [:]
    private(set) var providerStatusLoading: Set<ProviderID> = []
    private(set) var providerPromptFiring: Set<ProviderID> = []
    private(set) var providerPromptLastError: [ProviderID: String] = [:]
    private(set) var providerPromptLastFiredAt: [ProviderID: Date] = [:]

    init() {
        Task { await self.bootstrap() }
    }

    func bootstrap() async {
        do {
            let paths = try AppPaths.live()
            self.paths = paths
            let db = try Database.open(at: paths.databaseURL)
            self.database = db
            try await Seed.runIfNeeded(database: db)

            let providerRepo = GRDBProviderRepository(database: db)
            let cmdRepo = GRDBCommandRunRepository(database: db)
            let sweptCount = try await cmdRepo.sweepStaleRunning(message: "orphaned by app restart")
            if sweptCount > 0 {
                NSLog("Swept \(sweptCount) stale running command runs at startup")
            }

            let settingsRepo = GRDBAppSettingsRepository(database: db)

            self.providerRepository = providerRepo
            self.plannedWindowRepository = GRDBPlannedWindowRepository(database: db)
            self.actualWindow5hRepository = GRDBActualWindow5hRepository(database: db)
            self.actualWindow7dRepository = GRDBActualWindow7dRepository(database: db)
            self.scheduledPromptRepository = GRDBScheduledPromptRepository(database: db)
            self.commandRunRepository = cmdRepo
            self.usageSnapshotRepository = GRDBUsageSnapshotRepository(database: db)
            self.promptTemplateRepository = GRDBPromptTemplateRepository(database: db)
            self.appSettingsRepository = settingsRepo
            self.helperHeartbeatRepository = GRDBHelperHeartbeatRepository(database: db)

            self.providers = try await providerRepo.fetchAll()

            let resolver = DefaultCLIPathResolver()
            self.cliPathResolver = resolver
            let logWriter = DiskLogWriter(baseDirectory: paths.commandRunsDirectory)
            let runner = CommandRunner(
                logWriter: logWriter,
                onStart: { [cmdRepo] run in try await cmdRepo.create(run) },
                onComplete: { [cmdRepo] run in try await cmdRepo.update(run) }
            )
            self.commandRunner = runner
            let registry = ProviderRegistry(adapters: [
                ClaudeProviderAdapter(
                    runner: runner,
                    resolver: resolver,
                    appSettings: settingsRepo,
                    cmdRepo: cmdRepo,
                    logWriter: logWriter
                ),
                CodexProviderAdapter(
                    runner: runner,
                    resolver: resolver,
                    appSettings: settingsRepo,
                    cmdRepo: cmdRepo,
                    logWriter: logWriter
                )
            ])
            self.providerRegistry = registry

            if let scheduledRepo = self.scheduledPromptRepository,
               let actual5hRepo = self.actualWindow5hRepository,
               let actual7dRepo = self.actualWindow7dRepository,
               let usageRepo = self.usageSnapshotRepository {
                let driver = AppSchedulerDriver(
                    scheduledRepository: scheduledRepo,
                    actual5hRepository: actual5hRepo,
                    actual7dRepository: actual7dRepo,
                    usageSnapshotRepository: usageRepo,
                    registry: registry
                )
                let scheduler = SchedulerService(driver: driver)
                let ticker = SchedulerTicker(scheduler: scheduler)
                self.schedulerTicker = ticker
                ticker.start()
            }

            self.loadState = .ready
            Task { await self.refreshAllProviderStatuses() }
        } catch {
            self.loadState = .failed(String(describing: error))
            NSLog("AppEnvironment bootstrap failed: \(error)")
        }
    }

    func refreshAllProviderStatuses() async {
        for id in ProviderID.allCases {
            await refreshProviderStatus(id: id)
        }
    }

    @discardableResult
    func refreshProviderStatus(id: ProviderID) async -> ProviderStatus {
        providerStatusLoading.insert(id)
        defer { providerStatusLoading.remove(id) }

        let versionStatus = await runProviderVersionStatus(id: id, managesLoading: false)
        guard versionStatus.isInstalled, versionStatus.errorMessage == nil else {
            return versionStatus
        }
        return await runProviderAuthStatus(id: id, managesLoading: false)
    }

    @discardableResult
    func runProviderVersionStatus(id: ProviderID, managesLoading: Bool = true) async -> ProviderStatus {
        if managesLoading { providerStatusLoading.insert(id) }
        defer { if managesLoading { providerStatusLoading.remove(id) } }

        do {
            let adapter = try providerAdapter(for: id)
            var status = await adapter.runVersionCommand()
            if status.isInstalled {
                status.isAuthenticated = providerStatuses[id]?.isAuthenticated
            }
            providerStatuses[id] = status
            return status
        } catch {
            let status = ProviderStatus(
                providerID: id,
                isInstalled: false,
                errorMessage: String(describing: error)
            )
            providerStatuses[id] = status
            return status
        }
    }

    @discardableResult
    func runProviderAuthStatus(id: ProviderID, managesLoading: Bool = true) async -> ProviderStatus {
        if managesLoading { providerStatusLoading.insert(id) }
        defer { if managesLoading { providerStatusLoading.remove(id) } }

        do {
            let adapter = try providerAdapter(for: id)
            let authStatus = await adapter.runAuthStatusCommand()
            let existing = providerStatuses[id]
            let status = ProviderStatus(
                providerID: id,
                isInstalled: existing?.isInstalled ?? authStatus.isInstalled,
                cliPath: authStatus.cliPath ?? existing?.cliPath,
                version: existing?.version,
                isAuthenticated: authStatus.isAuthenticated,
                lastCheckedAt: authStatus.lastCheckedAt,
                errorMessage: authStatus.errorMessage
            )
            providerStatuses[id] = status
            return status
        } catch {
            let status = ProviderStatus(
                providerID: id,
                isInstalled: providerStatuses[id]?.isInstalled ?? false,
                cliPath: providerStatuses[id]?.cliPath,
                version: providerStatuses[id]?.version,
                isAuthenticated: providerStatuses[id]?.isAuthenticated,
                errorMessage: String(describing: error)
            )
            providerStatuses[id] = status
            return status
        }
    }

    func runProviderPromptCommand(id: ProviderID) async {
        guard !providerPromptFiring.contains(id) else { return }
        providerPromptFiring.insert(id)
        defer { providerPromptFiring.remove(id) }

        do {
            let prompt = await currentWakePrompt(for: id)
            let adapter = try providerAdapter(for: id)
            let input = TriggerPromptInput(prompt: prompt, projectPath: nil, mode: .newSession)
            _ = try await adapter.runPromptCommand(input)
            providerPromptLastFiredAt[id] = .now
            providerPromptLastError[id] = nil
        } catch {
            providerPromptLastError[id] = String(describing: error)
        }
    }

    private func currentWakePrompt(for id: ProviderID) async -> String {
        guard let appSettingsRepository else {
            return AppSettingsKeys.defaultWakePromptFallback
        }
        let key = AppSettingsKeys.defaultWakePrompt(for: id)
        let stored = (try? await appSettingsRepository.get(key, as: String.self)) ?? nil
        let trimmed = (stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppSettingsKeys.defaultWakePromptFallback : trimmed
    }

    private func providerAdapter(for id: ProviderID) throws -> any ProviderAdapter {
        guard let providerRegistry else {
            throw C5hError.providerNotConfigured(id.rawValue)
        }
        return try providerRegistry.adapter(for: id)
    }
}
