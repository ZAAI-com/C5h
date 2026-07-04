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
    private(set) var schedulerDriver: AppSchedulerDriver?
    private(set) var schedulerTicker: SchedulerTicker?
    private(set) var databaseChangeMonitor: DatabaseChangeMonitor?
    private(set) var providerStatuses: [ProviderID: ProviderStatus] = [:]
    private(set) var providerStatusLoading: Set<ProviderID> = []
    private(set) var providerPromptFiring: Set<ProviderID> = []
    private(set) var providerPromptLastError: [ProviderID: String] = [:]
    private(set) var providerPromptLastFiredAt: [ProviderID: Date] = [:]

    // Created synchronously rather than in bootstrap(): the updater has no
    // database dependency, and the update menu/Settings must work even when
    // the database load fails.
    let updaterService = UpdaterService()

    init() {
        Task { await self.bootstrap() }
    }

    func bootstrap() async {
        do {
            let paths = try AppPaths.live()
            self.paths = paths
            let db = try Database.open(at: paths.databaseURL)
            self.database = db
            // Reuse the monitor across bootstrap retries: replacing it would
            // deallocate an instance whose raw pointer is still registered with
            // the Darwin notify center.
            if databaseChangeMonitor == nil {
                let changeMonitor = DatabaseChangeMonitor()
                self.databaseChangeMonitor = changeMonitor
                changeMonitor.start()
            }
            try await Seed.runIfNeeded(database: db)

            let providerRepo = GRDBProviderRepository(database: db)
            let cmdRepo = GRDBCommandRunRepository(database: db)
            let sweptCount = try await cmdRepo.sweepStaleRunning(message: "orphaned by app restart")
            if sweptCount > 0 {
                NSLog("Swept \(sweptCount) stale running command runs at startup")
            }
            if let sweptUsageProbes = try? ClaudeUsageProbeSweeper().sweepOrphanedUsageProbes(),
               sweptUsageProbes > 0 {
                NSLog("Swept \(sweptUsageProbes) orphaned Claude usage probe processes at startup")
            }

            let settingsRepo = GRDBAppSettingsRepository(database: db)
            let plannedRepo = GRDBPlannedWindowRepository(database: db)
            let actual5hRepo = GRDBActualWindow5hRepository(database: db)
            let actual7dRepo = GRDBActualWindow7dRepository(database: db)
            let scheduledRepo = GRDBScheduledPromptRepository(database: db)
            let repairedPlannedCount = try await scheduledRepo.reconcileLinkedPlannedWindowStatuses()
            if repairedPlannedCount > 0 {
                NSLog("Reconciled \(repairedPlannedCount) planned window statuses from scheduled prompts")
            }

            self.providerRepository = providerRepo
            self.plannedWindowRepository = plannedRepo
            self.actualWindow5hRepository = actual5hRepo
            self.actualWindow7dRepository = actual7dRepo
            self.scheduledPromptRepository = scheduledRepo
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
                self.schedulerDriver = driver
                let scheduler = SchedulerService(driver: driver)
                let ticker = SchedulerTicker(scheduler: scheduler)
                self.schedulerTicker = ticker
                ticker.start()
            }

            self.loadState = .ready
            Task { await self.refreshAllProviderStatuses() }
            #if !DEBUG
            Task { await self.restartHelperIfOutdated() }
            #endif
        } catch {
            self.loadState = .failed(String(describing: error))
            NSLog("AppEnvironment bootstrap failed: \(error)")
        }
    }

    #if !DEBUG
    /// Restarts the LaunchAgent helper at launch when the running process predates
    /// the helper binary in the current app bundle (skew after a rebuild) or has
    /// stopped. Without this, a long-lived helper keeps running stale code (e.g. a
    /// pre-fix build that fabricates phantom 5h windows) until the user notices.
    /// `KeepAlive` relaunches the fresh binary; the next heartbeat clears the skew.
    private func restartHelperIfOutdated() async {
        guard let repo = helperHeartbeatRepository else { return }
        let latest = try? await repo.latest()
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/C5hHelper")
        let evaluation = HelperHealthEvaluator().evaluate(
            heartbeat: latest.map {
                HelperHeartbeatEvidence(startedAt: $0.startedAt, lastSeenAt: $0.lastSeenAt, pid: $0.pid)
            },
            now: .now,
            expectedBinaryModifiedAt: HelperBuildStamp.modificationDate(forBinaryAt: helperURL),
            isProcessAlive: { ProcessLivenessChecker.isAlive(pid: $0) }
        )
        // A helper that died more than `staleAfterSeconds` ago reports `.stale`
        // (the evaluator returns `.stale` before it ever checks liveness), so the
        // common "long-dead at launch" case must be repaired here too, not only
        // the narrow `.stopped` window.
        guard evaluation.outdated
            || evaluation.status == .stopped
            || evaluation.status == .stale else { return }
        let reason = evaluation.outdated ? "outdated" : String(describing: evaluation.status)
        NSLog("AppEnvironment: helper \(reason) (pid \(evaluation.pid.map(String.init) ?? "nil")); restarting")
        // Only signal a confirmed-live PID. `.stale` is reported before any
        // liveness check and `.stopped` is a dead PID, so passing them risks a
        // stray SIGTERM to a recycled PID (common after a reboot) while skipping
        // the register() that would actually bring the helper back. Mirror
        // SettingsView.restartHelper(): pass nil for those states so restart()
        // registers instead.
        let runningPID = evaluation.status == .running ? evaluation.pid : nil
        HelperRegistrationService().restart(runningPID: runningPID)
    }
    #endif

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
            let run = try await adapter.runPromptCommand(input)
            providerPromptLastFiredAt[id] = .now
            providerPromptLastError[id] = nil
            // Anchor a 5h window for this manual trigger the same way the
            // scheduler does. A resolver failure must not surface as a prompt
            // failure (the command already ran); log and move on, mirroring
            // SchedulerService.tick.
            do {
                _ = try await schedulerDriver?.resolveActualWindow(for: id, commandRun: run)
            } catch {
                NSLog("AppEnvironment: resolveActualWindow failed for manual \(id.rawValue) trigger: \(error)")
            }
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
