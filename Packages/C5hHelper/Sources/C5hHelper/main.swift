import Foundation
import C5hCore
import C5hStore

@main
struct HelperMain {
    static func main() async {
        let helperVersion = "0.0.1"

        let appSupport: URL
        do {
            appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("C5h", isDirectory: true)
            try FileManager.default.createDirectory(
                at: appSupport,
                withIntermediateDirectories: true
            )
        } catch {
            NSLog("C5hHelper: cannot create app support dir: \(error)")
            exit(1)
        }

        // Redirect stdout/stderr into the app's log directory so launchd doesn't
        // need StandardOutPath/StandardErrorPath (which can't expand ~).
        let helperLogsDir = appSupport.appendingPathComponent("logs", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: helperLogsDir, withIntermediateDirectories: true)
        } catch {
            NSLog("C5hHelper: cannot create logs dir at \(helperLogsDir.path): \(error)")
            exit(1)
        }
        guard freopen(helperLogsDir.appendingPathComponent("com.zaai.c5h.helper.out.log").path, "a", stdout) != nil else {
            NSLog("C5hHelper: failed to redirect stdout to \(helperLogsDir.path)")
            exit(1)
        }
        guard freopen(helperLogsDir.appendingPathComponent("com.zaai.c5h.helper.err.log").path, "a", stderr) != nil else {
            NSLog("C5hHelper: failed to redirect stderr to \(helperLogsDir.path)")
            exit(1)
        }

        NSLog("C5hHelper \(helperVersion) starting (pid \(getpid()))")
        let dbURL = appSupport.appendingPathComponent("c5h.sqlite")

        let database: Database
        do {
            database = try Database.open(at: dbURL)
        } catch {
            NSLog("C5hHelper: cannot open db: \(error)")
            exit(2)
        }

        let heartbeatRepo = GRDBHelperHeartbeatRepository(database: database)
        let scheduledRepo = GRDBScheduledPromptRepository(database: database)
        let actualRepo = GRDBActualWindowRepository(database: database)
        let cmdRepo = GRDBCommandRunRepository(database: database)
        let usageRepo = GRDBUsageSnapshotRepository(database: database)
        let _ = try? await cmdRepo.sweepStaleRunning(message: "orphaned by helper restart")

        let logsDir = appSupport
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("command-runs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let logWriter = DiskLogWriter(baseDirectory: logsDir)
        let runner = CommandRunner(
            logWriter: logWriter,
            onStart: { run in try await cmdRepo.create(run) },
            onComplete: { run in try await cmdRepo.update(run) }
        )
        let resolver = DefaultCLIPathResolver()
        let settingsRepo = GRDBAppSettingsRepository(database: database)

        let driver = HelperSchedulerDriver(
            scheduledRepo: scheduledRepo,
            actualRepo: actualRepo,
            runner: runner,
            resolver: resolver,
            settingsRepo: settingsRepo
        )
        let scheduler = SchedulerService(driver: driver)

        let usageFetcher = UsageFetcher(
            persistSnapshot: { snapshot in try await usageRepo.create(snapshot) },
            upsertActualWindow: { window, tolerance in
                try await actualRepo.upsertByEndAt(window, tolerance: tolerance)
            }
        )
        let usageRefresher = HelperUsageRefresher(
            resolver: resolver,
            settingsRepo: settingsRepo,
            fetcher: usageFetcher,
            intervalSeconds: 5 * 60
        )

        // Heartbeat + tick loop. Sleep 30s between iterations.
        while true {
            try? await heartbeatRepo.writeHeartbeat(
                version: helperVersion,
                pid: Int(getpid())
            )
            _ = await scheduler.tick(now: .now)
            await usageRefresher.tickIfDue(now: .now)
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
        }
    }
}

/// Polls every enabled provider's usage on a fixed cadence so the "current 5h
/// window" we display stays accurate even when the main app isn't open.
actor HelperUsageRefresher {
    let resolver: any CLIPathResolving
    let settingsRepo: any AppSettingsRepository
    let fetcher: UsageFetcher
    let intervalSeconds: TimeInterval

    private var lastRefreshAt: Date?

    init(
        resolver: any CLIPathResolving,
        settingsRepo: any AppSettingsRepository,
        fetcher: UsageFetcher,
        intervalSeconds: TimeInterval
    ) {
        self.resolver = resolver
        self.settingsRepo = settingsRepo
        self.fetcher = fetcher
        self.intervalSeconds = intervalSeconds
    }

    func tickIfDue(now: Date) async {
        if let last = lastRefreshAt, now.timeIntervalSince(last) < intervalSeconds {
            return
        }
        lastRefreshAt = now
        for providerID in ProviderID.allCases {
            await refresh(providerID: providerID, now: now)
        }
    }

    private func refresh(providerID: ProviderID, now: Date) async {
        do {
            let configured = try? await settingsRepo.get(
                AppSettingsKeys.cliPath(for: providerID),
                as: String.self
            )
            guard let cliURL = await resolver.resolveCLI(
                named: providerID.executableName,
                configuredPath: configured
            ) else {
                return
            }
            let snapshot: UsageSnapshot
            switch providerID {
            case .claude:
                snapshot = try await ClaudeUsageCollector(executableURL: cliURL).collect()
            case .codex:
                snapshot = try await CodexUsageCollector(executableURL: cliURL).collect()
            }
            try await fetcher.persistSnapshot(snapshot)
            for window in try fetcher.derivedActualWindows(from: snapshot, now: now) {
                try await fetcher.upsertActualWindow(window, UsageFetcher.dedupTolerance)
            }
        } catch {
            NSLog("C5hHelper: usage refresh failed for \(providerID.rawValue): \(error)")
        }
    }
}

struct HelperSchedulerDriver: SchedulerDriver {
    let scheduledRepo: any ScheduledPromptRepository
    let actualRepo: any ActualWindowRepository
    let runner: any CommandRunning
    let resolver: any CLIPathResolving
    let settingsRepo: any AppSettingsRepository

    func fetchDuePrompts(now: Date) async throws -> [ScheduledPrompt] {
        try await scheduledRepo.fetchDuePrompts(now: now)
    }

    func claimAsRunning(id: UUID) async throws -> Bool {
        try await scheduledRepo.tryClaimAsRunning(id: id)
    }

    func markSucceeded(id: UUID) async throws {
        try await scheduledRepo.markSucceeded(id: id)
    }

    func markFailed(id: UUID, error: String) async throws {
        try await scheduledRepo.markFailed(id: id, error: error)
    }

    func markMissed(id: UUID) async throws {
        try await scheduledRepo.markMissed(id: id)
    }

    func registerActualWindow(_ window: ActualWindow) async throws {
        try await actualRepo.create(window)
    }

    func trigger(prompt: ScheduledPrompt) async throws -> CommandRun {
        let key = "providers.\(prompt.providerID.rawValue).cliPath"
        let configured = try await settingsRepo.get(key, as: String.self)
        guard let cliURL = await resolver.resolveCLI(
            named: prompt.providerID.executableName,
            configuredPath: configured
        ) else {
            throw C5hError.cliNotFound(prompt.providerID.executableName)
        }
        return try await runner.run(PromptCommand(
            providerID: prompt.providerID,
            executableURL: cliURL,
            input: TriggerPromptInput(
                prompt: prompt.prompt,
                projectPath: prompt.projectPath,
                mode: .newSession
            )
        ).spec())
    }
}
