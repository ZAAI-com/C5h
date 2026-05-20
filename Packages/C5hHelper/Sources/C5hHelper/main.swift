import Foundation
import C5hCore
import C5hStore

@main
struct HelperMain {
    static func main() async {
        let helperVersion = "0.0.1"
        NSLog("C5hHelper \(helperVersion) starting (pid \(getpid()))")

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

        // Heartbeat + tick loop. Sleep 30s between iterations.
        while true {
            try? await heartbeatRepo.writeHeartbeat(
                version: helperVersion,
                pid: Int(getpid())
            )
            _ = await scheduler.tick(now: .now)
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
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
        let configured = try? await settingsRepo.get(key, as: String.self)
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
