import Foundation
import C5hCore
import C5hStore

@main
struct HelperMain {
    static func main() async {
        let helperBinaryURL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        let helperVersion = HelperAppVersion.version(forHelperAt: helperBinaryURL)

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
        // Keep the Debug helper's logs separate from the production helper's so a
        // dev build sharing the same data directory doesn't interleave log files.
        #if DEBUG
        let helperLabel = "com.zaai.c5h.debug.helper"
        #else
        let helperLabel = "com.zaai.c5h.helper"
        #endif
        guard freopen(helperLogsDir.appendingPathComponent("\(helperLabel).out.log").path, "a", stdout) != nil else {
            NSLog("C5hHelper: failed to redirect stdout to \(helperLogsDir.path)")
            exit(1)
        }
        guard freopen(helperLogsDir.appendingPathComponent("\(helperLabel).err.log").path, "a", stderr) != nil else {
            NSLog("C5hHelper: failed to redirect stderr to \(helperLogsDir.path)")
            exit(1)
        }

        NSLog("C5hHelper \(helperVersion) starting (pid \(getpid()))")
        if let sweptUsageProbes = try? ClaudeUsageProbeSweeper().sweepOrphanedUsageProbes(),
           sweptUsageProbes > 0 {
            NSLog("C5hHelper: swept \(sweptUsageProbes) orphaned Claude usage probe processes at startup")
        }
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
        let actual5hRepo = GRDBActualWindow5hRepository(database: database)
        let actual7dRepo = GRDBActualWindow7dRepository(database: database)
        let plannedRepo = GRDBPlannedWindowRepository(database: database)
        let cmdRepo = GRDBCommandRunRepository(database: database)
        let usageRepo = GRDBUsageSnapshotRepository(database: database)
        let _ = try? await cmdRepo.sweepStaleRunning(message: "orphaned by helper restart")
        if let repaired = try? await scheduledRepo.reconcileLinkedPlannedWindowStatuses(), repaired > 0 {
            NSLog("C5hHelper: reconciled \(repaired) planned window statuses from scheduled prompts")
        }

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

        let usageFetcher = UsageFetcher(
            persistSnapshot: { snapshot in try await usageRepo.create(snapshot) },
            upsertActualWindow5h: { window, tolerance in
                try await actual5hRepo.upsertByEndAt(window, tolerance: tolerance)
            },
            upsertActualWindow7d: { window, tolerance in
                try await actual7dRepo.upsertByEndAt(window, tolerance: tolerance)
            }
        )
        let driver = HelperSchedulerDriver(
            scheduledRepo: scheduledRepo,
            actual5hRepo: actual5hRepo,
            runner: runner,
            resolver: resolver,
            settingsRepo: settingsRepo,
            usageFetcher: usageFetcher,
            cmdRepo: cmdRepo,
            logWriter: logWriter
        )
        let scheduler = SchedulerService(driver: driver)

        let usageRefresher = HelperUsageRefresher(
            resolver: resolver,
            settingsRepo: settingsRepo,
            fetcher: usageFetcher,
            cmdRepo: cmdRepo,
            logWriter: logWriter,
            actual5hRepo: actual5hRepo,
            plannedRepo: plannedRepo
        )

        // Heartbeat + tick loop. Sleep 30s between iterations. Exit after a bounded
        // uptime so launchd (KeepAlive) relaunches a fresh process; this is the
        // periodic restart and also self-heals version skew after an app rebuild,
        // since the relaunch picks up the current bundle's helper binary.
        let startedAt = Date()
        while true {
            try? await heartbeatRepo.writeHeartbeat(
                version: helperVersion,
                pid: Int(getpid())
            )
            _ = await scheduler.tick(now: .now)
            await usageRefresher.tickIfDue(now: .now)
            if HelperRestartPolicy.shouldRestart(startedAt: startedAt, now: .now) {
                NSLog("C5hHelper \(helperVersion) exiting for periodic restart after \(Int(Date().timeIntervalSince(startedAt)))s uptime (pid \(getpid()))")
                exit(2)
            }
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
        }
    }
}

/// Polls each provider's usage on its own configured cadence so the "current 5h
/// window" we display stays accurate even when the main app isn't open. Honors
/// the per-provider "check when idle" setting: when off, a provider is skipped
/// unless it has an active or pending planned window.
actor HelperUsageRefresher {
    let resolver: any CLIPathResolving
    let settingsRepo: any AppSettingsRepository
    let fetcher: UsageFetcher
    let cmdRepo: any CommandRunRepository
    let logWriter: any FileLogWriting
    let gate: UsageCheckGate

    private var lastRefreshAt: [ProviderID: Date] = [:]

    init(
        resolver: any CLIPathResolving,
        settingsRepo: any AppSettingsRepository,
        fetcher: UsageFetcher,
        cmdRepo: any CommandRunRepository,
        logWriter: any FileLogWriting,
        actual5hRepo: any ActualWindow5hRepository,
        plannedRepo: any PlannedWindowRepository
    ) {
        self.resolver = resolver
        self.settingsRepo = settingsRepo
        self.fetcher = fetcher
        self.cmdRepo = cmdRepo
        self.logWriter = logWriter
        self.gate = UsageCheckGate.make(
            appSettings: settingsRepo,
            actual5hRepository: actual5hRepo,
            plannedWindowRepository: plannedRepo
        )
    }

    func tickIfDue(now: Date) async {
        for providerID in ProviderID.allCases {
            let interval = await intervalSeconds(for: providerID)
            if let last = lastRefreshAt[providerID], now.timeIntervalSince(last) < interval {
                continue
            }
            // Don't consume the interval when gated off: re-evaluate next tick so
            // a newly active or planned window resumes polling promptly.
            guard await gate.shouldCheck(providerID: providerID, now: now) else {
                continue
            }
            if await refresh(providerID: providerID, now: now) {
                lastRefreshAt[providerID] = now
            }
        }
    }

    private func intervalSeconds(for providerID: ProviderID) async -> TimeInterval {
        let stored = (try? await settingsRepo.get(
            AppSettingsKeys.usageRefreshIntervalSeconds(for: providerID),
            as: Int.self
        )) ?? nil
        return TimeInterval(stored ?? AppSettingsKeys.defaultUsageRefreshIntervalSeconds)
    }

    /// Returns true when the provider's interval should be consumed. A lock
    /// collision means another process is already refreshing, so the helper
    /// should retry on the next tick instead of sleeping for the full interval.
    private func refresh(providerID: ProviderID, now: Date) async -> Bool {
        do {
            let configured = try? await settingsRepo.get(
                AppSettingsKeys.cliPath(for: providerID),
                as: String.self
            )
            guard let cliURL = await resolver.resolveCLI(
                named: providerID.executableName,
                configuredPath: configured
            ) else {
                return true
            }
            let snapshot: UsageSnapshot
            let repo = cmdRepo
            let writer = logWriter
            snapshot = try await UsageCommand(providerID: providerID, executableURL: cliURL).collect(
                logWriter: writer,
                onStart: { run in try await repo.create(run) },
                onComplete: { run in try await repo.update(run) }
            )
            try await fetcher.persistSnapshot(snapshot)
            if let window = try fetcher.derived5h(from: snapshot, now: now) {
                try await fetcher.upsertActualWindow5h(window, UsageFetcher.dedupTolerance)
            }
            if let window = try fetcher.derived7d(from: snapshot) {
                try await fetcher.upsertActualWindow7d(window, UsageFetcher.dedupTolerance)
            }
            return true
        } catch {
            if (error as? C5hError)?.isUsageRefreshAlreadyRunning == true {
                return false
            }
            NSLog("C5hHelper: usage refresh failed for \(providerID.rawValue): \(error)")
            return true
        }
    }
}

struct HelperSchedulerDriver: SchedulerDriver {
    let scheduledRepo: any ScheduledPromptRepository
    let actual5hRepo: any ActualWindow5hRepository
    let runner: any CommandRunning
    let resolver: any CLIPathResolving
    let settingsRepo: any AppSettingsRepository
    let usageFetcher: UsageFetcher
    let cmdRepo: any CommandRunRepository
    let logWriter: any FileLogWriting

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

    func trigger(prompt: ScheduledPrompt) async throws -> CommandRun {
        let cliURL = try await resolveCLI(for: prompt.providerID)
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

    func resolveActualWindow(
        for providerID: ProviderID,
        commandRun: CommandRun
    ) async throws -> ActualWindow5h? {
        let actual5hRepo = actual5hRepo
        let settingsRepo = settingsRepo
        let cliResolver = resolver
        let cmdRepo = cmdRepo
        let logWriter = logWriter
        let resolver = ActiveWindowResolver(
            fetcher: usageFetcher,
            snapshotFetch: { providerID in
                let cliURL = try await Self.resolveCLIStandalone(
                    for: providerID,
                    settingsRepo: settingsRepo,
                    resolver: cliResolver
                )
                return try await UsageCommand(providerID: providerID, executableURL: cliURL).collect(
                    logWriter: logWriter,
                    onStart: { run in try await cmdRepo.create(run) },
                    onComplete: { run in try await cmdRepo.update(run) }
                )
            },
            activeWindowFetch: { providerID, now in
                let interval = DateInterval(start: now, duration: 1)
                let windows = try await actual5hRepo.fetchWindows(for: interval)
                return windows.first { $0.providerID == providerID }
            },
            updateActualWindow: { window in
                try await actual5hRepo.update(window)
            }
        )
        return await resolver.resolveTriggeredWindow(
            providerID: providerID,
            commandRunID: commandRun.id,
            now: commandRun.startedAt
        )
    }

    private func resolveCLI(for providerID: ProviderID) async throws -> URL {
        try await Self.resolveCLIStandalone(
            for: providerID,
            settingsRepo: settingsRepo,
            resolver: resolver
        )
    }

    private static func resolveCLIStandalone(
        for providerID: ProviderID,
        settingsRepo: any AppSettingsRepository,
        resolver: any CLIPathResolving
    ) async throws -> URL {
        let key = AppSettingsKeys.cliPath(for: providerID)
        let configured = try await settingsRepo.get(key, as: String.self)
        guard let cliURL = await resolver.resolveCLI(
            named: providerID.executableName,
            configuredPath: configured
        ) else {
            throw C5hError.cliNotFound(providerID.executableName)
        }
        return cliURL
    }
}
