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
    private(set) var actualWindowRepository: (any ActualWindowRepository)?
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

            self.providerRepository = providerRepo
            self.plannedWindowRepository = GRDBPlannedWindowRepository(database: db)
            self.actualWindowRepository = GRDBActualWindowRepository(database: db)
            self.scheduledPromptRepository = GRDBScheduledPromptRepository(database: db)
            self.commandRunRepository = cmdRepo
            self.usageSnapshotRepository = GRDBUsageSnapshotRepository(database: db)
            self.promptTemplateRepository = GRDBPromptTemplateRepository(database: db)
            self.appSettingsRepository = GRDBAppSettingsRepository(database: db)
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
            let settingsRepo = GRDBAppSettingsRepository(database: db)
            self.appSettingsRepository = settingsRepo
            let registry = ProviderRegistry(adapters: [
                ClaudeProviderAdapter(runner: runner, resolver: resolver, appSettings: settingsRepo),
                CodexProviderAdapter(runner: runner, resolver: resolver, appSettings: settingsRepo)
            ])
            self.providerRegistry = registry

            if let scheduledRepo = self.scheduledPromptRepository,
               let actualRepo = self.actualWindowRepository {
                let driver = AppSchedulerDriver(
                    scheduledRepository: scheduledRepo,
                    actualRepository: actualRepo,
                    registry: registry
                )
                let scheduler = SchedulerService(driver: driver)
                let ticker = SchedulerTicker(scheduler: scheduler)
                self.schedulerTicker = ticker
                ticker.start()
            }

            #if DEBUG
            await LogsFixtureLoader.loadIfNeeded(repository: cmdRepo, appPaths: paths)
            await CalendarFixtureLoader.loadIfNeeded(
                plannedRepository: GRDBPlannedWindowRepository(database: db),
                actualRepository: GRDBActualWindowRepository(database: db)
            )
            #endif

            self.loadState = .ready
        } catch {
            self.loadState = .failed(String(describing: error))
            NSLog("AppEnvironment bootstrap failed: \(error)")
        }
    }
}
