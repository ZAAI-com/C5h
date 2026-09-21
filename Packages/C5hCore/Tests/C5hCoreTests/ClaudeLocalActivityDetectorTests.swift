import Foundation
import Testing
@testable import C5hCore

@Suite("ClaudeLocalActivityDetector")
struct ClaudeLocalActivityDetectorTests {
    private let reference = Date(timeIntervalSince1970: 1_000_000)

    @Test("Resolves projects under a custom Claude config directory")
    func resolvesCustomConfigDirectory() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let projects = ClaudeLocalActivityDetector.resolveProjectsDirectory(
            environment: ["CLAUDE_CONFIG_DIR": "/Volumes/Accounts/claude-work"],
            homeDirectory: home
        )

        #expect(projects.path == "/Volumes/Accounts/claude-work/projects")
    }

    @Test("Falls back to the home Claude directory when no config directory is set")
    func resolvesDefaultConfigDirectory() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

        #expect(ClaudeLocalActivityDetector.resolveProjectsDirectory(
            environment: [:],
            homeDirectory: home
        ).path == "/Users/tester/.claude/projects")
        #expect(ClaudeLocalActivityDetector.resolveProjectsDirectory(
            environment: ["CLAUDE_CONFIG_DIR": "  "],
            homeDirectory: home
        ).path == "/Users/tester/.claude/projects")
    }

    @Test("Expands a tilde in the Claude config directory")
    func expandsTildeInConfigDirectory() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

        #expect(ClaudeLocalActivityDetector.resolveProjectsDirectory(
            environment: ["CLAUDE_CONFIG_DIR": "~/accounts/personal"],
            homeDirectory: home
        ).path == "/Users/tester/accounts/personal/projects")
        #expect(ClaudeLocalActivityDetector.resolveProjectsDirectory(
            environment: ["CLAUDE_CONFIG_DIR": "~"],
            homeDirectory: home
        ).path == "/Users/tester/projects")
    }

    @Test("Reports no activity when the projects directory does not exist")
    func reportsNoActivityWhenProjectsDirectoryMissing() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5h-tests-missing-\(UUID().uuidString)", isDirectory: true)
        let detector = ClaudeLocalActivityDetector(
            projectsDirectory: missing,
            excludedProjectPaths: []
        )
        #expect(await detector.hasActivity(since: .distantPast) == false)
    }

    @Test("Detects a session file modified after the reference date")
    func detectsSessionFileModifiedAfterReference() async throws {
        let projects = try makeProjectsDirectory()
        defer { removeDirectory(projects) }
        try makeTranscript(
            in: projects,
            project: "-Users-m-Some-Project",
            name: "session.jsonl",
            modifiedAt: reference.addingTimeInterval(60)
        )
        let detector = ClaudeLocalActivityDetector(projectsDirectory: projects, excludedProjectPaths: [])
        #expect(await detector.hasActivity(since: reference))
    }

    @Test("Ignores a transcript modified after the scan time")
    func ignoresFutureDatedTranscript() async throws {
        let projects = try makeProjectsDirectory()
        defer { removeDirectory(projects) }
        let now = reference.addingTimeInterval(120)
        try makeTranscript(
            in: projects,
            project: "-Users-m-Some-Project",
            name: "future.jsonl",
            modifiedAt: now.addingTimeInterval(1)
        )
        let detector = ClaudeLocalActivityDetector(projectsDirectory: projects, excludedProjectPaths: [])

        #expect(await detector.hasActivity(since: reference, now: now) == false)
    }

    @Test("A future transcript does not hide valid current activity")
    func detectsValidActivityAlongsideFutureDatedTranscript() async throws {
        let projects = try makeProjectsDirectory()
        defer { removeDirectory(projects) }
        let now = reference.addingTimeInterval(120)
        try makeTranscript(
            in: projects,
            project: "-Users-m-Some-Project",
            name: "valid.jsonl",
            modifiedAt: now.addingTimeInterval(-1)
        )
        try makeTranscript(
            in: projects,
            project: "-Users-m-Some-Project",
            name: "future.jsonl",
            modifiedAt: now.addingTimeInterval(1)
        )
        let detector = ClaudeLocalActivityDetector(projectsDirectory: projects, excludedProjectPaths: [])

        #expect(await detector.hasActivity(since: reference, now: now))
    }

    @Test("Accepts a transcript modified exactly at the scan time")
    func acceptsTranscriptAtScanTime() async throws {
        let projects = try makeProjectsDirectory()
        defer { removeDirectory(projects) }
        let now = reference.addingTimeInterval(120)
        try makeTranscript(
            in: projects,
            project: "-Users-m-Some-Project",
            name: "current.jsonl",
            modifiedAt: now
        )
        let detector = ClaudeLocalActivityDetector(projectsDirectory: projects, excludedProjectPaths: [])

        #expect(await detector.hasActivity(since: reference, now: now))
    }

    @Test("Ignores session files modified at or before the reference date")
    func ignoresFilesModifiedBeforeReference() async throws {
        let projects = try makeProjectsDirectory()
        defer { removeDirectory(projects) }
        try makeTranscript(
            in: projects,
            project: "-Users-m-Some-Project",
            name: "old.jsonl",
            modifiedAt: reference.addingTimeInterval(-60)
        )
        try makeTranscript(
            in: projects,
            project: "-Users-m-Some-Project",
            name: "exact.jsonl",
            modifiedAt: reference
        )
        let detector = ClaudeLocalActivityDetector(projectsDirectory: projects, excludedProjectPaths: [])
        #expect(await detector.hasActivity(since: reference) == false)
    }

    @Test("Ignores non-transcript files")
    func ignoresNonJSONLFiles() async throws {
        let projects = try makeProjectsDirectory()
        defer { removeDirectory(projects) }
        try makeTranscript(
            in: projects,
            project: "-Users-m-Some-Project",
            name: "notes.txt",
            modifiedAt: reference.addingTimeInterval(60)
        )
        try makeTranscript(
            in: projects,
            project: "-Users-m-Some-Project",
            name: "data.json",
            modifiedAt: reference.addingTimeInterval(60)
        )
        let detector = ClaudeLocalActivityDetector(projectsDirectory: projects, excludedProjectPaths: [])
        #expect(await detector.hasActivity(since: reference) == false)
    }

    @Test("Detects activity in nested subdirectories")
    func detectsActivityInNestedSubdirectories() async throws {
        let projects = try makeProjectsDirectory()
        defer { removeDirectory(projects) }
        try makeTranscript(
            in: projects,
            project: "-Users-m-Some-Project/subagents/deep",
            name: "nested.jsonl",
            modifiedAt: reference.addingTimeInterval(60)
        )
        let detector = ClaudeLocalActivityDetector(projectsDirectory: projects, excludedProjectPaths: [])
        #expect(await detector.hasActivity(since: reference))
    }

    @Test("Excludes the usage probe's own project directory")
    func excludesUsageProbeProjectDirectory() async throws {
        let projects = try makeProjectsDirectory()
        defer { removeDirectory(projects) }
        let probeCwd = URL(fileURLWithPath: "/Users/m/Library/Application Support/C5h")
        let encoded = ClaudeLocalActivityDetector.encodedProjectDirectoryName(forPath: probeCwd.path)
        try makeTranscript(
            in: projects,
            project: encoded,
            name: "probe-session.jsonl",
            modifiedAt: reference.addingTimeInterval(60)
        )
        let detector = ClaudeLocalActivityDetector(
            projectsDirectory: projects,
            excludedProjectPaths: [probeCwd]
        )
        #expect(await detector.hasActivity(since: reference) == false)
    }

    @Test("Excludes the real usage-probe working directory end to end")
    func excludesRealProbeWorkingDirectoryEndToEnd() async throws {
        // Exercise the production wiring (defaultExcludedProjectPaths ->
        // ClaudeUsageCollector.probeWorkingDirectory() -> encoded name) rather
        // than a hand-built path, so a drift in the real probe-cwd encoding
        // would fail here instead of silently breaking self-exclusion.
        let probeCwd = ClaudeUsageCollector.probeWorkingDirectory()
        let encoded = ClaudeLocalActivityDetector.encodedProjectDirectoryName(forPath: probeCwd.path)
        let projects = try makeProjectsDirectory()
        defer { removeDirectory(projects) }
        try makeTranscript(
            in: projects,
            project: encoded,
            name: "probe-session.jsonl",
            modifiedAt: reference.addingTimeInterval(60)
        )
        let detector = ClaudeLocalActivityDetector(
            projectsDirectory: projects,
            excludedProjectPaths: ClaudeLocalActivityDetector.defaultExcludedProjectPaths
        )
        // The default exclusion must actually resolve and encode the probe cwd.
        #expect(detector.excludedProjectDirectoryNames.contains(encoded))
        #expect(await detector.hasActivity(since: reference) == false)
    }

    @Test("Encodes project paths like Claude Code")
    func encodesProjectPathsLikeClaudeCode() {
        // Pinned against the real layout: slash, space, and dot all become "-".
        #expect(
            ClaudeLocalActivityDetector.encodedProjectDirectoryName(
                forPath: "/Users/m/Library/Application Support/C5h"
            ) == "-Users-m-Library-Application-Support-C5h"
        )
        #expect(
            ClaudeLocalActivityDetector.encodedProjectDirectoryName(forPath: "/Users/m/.claude")
                == "-Users-m--claude"
        )
    }

    @Test("Fails closed when the scan cap is exceeded")
    func failsClosedWhenScanCapExceeded() async throws {
        let projects = try makeProjectsDirectory()
        defer { removeDirectory(projects) }
        try makeTranscript(
            in: projects,
            project: "-Users-m-Some-Project",
            name: "fresh.jsonl",
            modifiedAt: reference.addingTimeInterval(60)
        )
        let detector = ClaudeLocalActivityDetector(
            projectsDirectory: projects,
            excludedProjectPaths: [],
            maxScannedFiles: 0
        )
        #expect(await detector.hasActivity(since: reference) == false)
    }

    @Test("Caches a completed walk until the requested rescan interval expires")
    func cachesCompletedWalkUntilIntervalExpires() async throws {
        let projects = try makeProjectsDirectory()
        defer { removeDirectory(projects) }
        let detector = ClaudeLocalActivityDetector(
            projectsDirectory: projects,
            excludedProjectPaths: []
        )
        let firstScanAt = reference.addingTimeInterval(120)

        #expect(await detector.hasActivity(
            since: reference,
            now: firstScanAt,
            minimumRescanInterval: 300
        ) == false)

        try makeTranscript(
            in: projects,
            project: "-Users-m-Some-Project",
            name: "new-session.jsonl",
            modifiedAt: reference.addingTimeInterval(60)
        )
        #expect(await detector.hasActivity(
            since: reference,
            now: firstScanAt.addingTimeInterval(299),
            minimumRescanInterval: 300
        ) == false)
        #expect(await detector.hasActivity(
            since: reference,
            now: firstScanAt.addingTimeInterval(300),
            minimumRescanInterval: 300
        ))
    }

    @Test("Cached latest modification date is evaluated against each reference")
    func cachedLatestDateUsesEachReference() async throws {
        let projects = try makeProjectsDirectory()
        defer { removeDirectory(projects) }
        let project = "-Users-m-Some-Project"
        let name = "session.jsonl"
        let modificationDate = reference.addingTimeInterval(60)
        try makeTranscript(
            in: projects,
            project: project,
            name: name,
            modifiedAt: modificationDate
        )
        let detector = ClaudeLocalActivityDetector(
            projectsDirectory: projects,
            excludedProjectPaths: []
        )
        let firstScanAt = reference.addingTimeInterval(120)
        #expect(await detector.hasActivity(
            since: reference,
            now: firstScanAt,
            minimumRescanInterval: 300
        ))

        // Removing the source proves both following answers come from the same
        // cached latest date rather than another filesystem walk.
        try FileManager.default.removeItem(
            at: projects
                .appendingPathComponent(project, isDirectory: true)
                .appendingPathComponent(name)
        )
        #expect(await detector.hasActivity(
            since: reference.addingTimeInterval(30),
            now: firstScanAt.addingTimeInterval(1),
            minimumRescanInterval: 300
        ))
        #expect(await detector.hasActivity(
            since: modificationDate,
            now: firstScanAt.addingTimeInterval(2),
            minimumRescanInterval: 300
        ) == false)
    }

    @Test("Concurrent cache callers coalesce onto one filesystem scan")
    func concurrentCallersCoalesce() async {
        let cache = ClaudeLocalActivityScanCache()
        let counter = LockedCounter()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        await withTaskGroup(of: ClaudeLocalActivityScanResult.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await cache.result(now: now, minimumRescanInterval: 300) {
                        counter.increment()
                        Thread.sleep(forTimeInterval: 0.05)
                        return .completed(latestModificationDate: nil)
                    }
                }
            }
            for await result in group {
                #expect(result == .completed(latestModificationDate: nil))
            }
        }

        #expect(counter.value == 1)
    }

    @Test("Scan-limit failures are cached until the interval expires")
    func limitExceededIsCachedUntilExpiry() async {
        let cache = ClaudeLocalActivityScanCache()
        let counter = LockedCounter()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let scan: @Sendable () -> ClaudeLocalActivityScanResult = {
            counter.increment()
            return .limitExceeded
        }

        let initial = await cache.result(
            now: now,
            minimumRescanInterval: 300,
            scan: scan
        )
        let cached = await cache.result(
            now: now.addingTimeInterval(299),
            minimumRescanInterval: 300,
            scan: scan
        )
        #expect(initial == .limitExceeded)
        #expect(cached == .limitExceeded)
        #expect(counter.value == 1)

        let expired = await cache.result(
            now: now.addingTimeInterval(300),
            minimumRescanInterval: 300,
            scan: scan
        )
        #expect(expired == .limitExceeded)
        #expect(counter.value == 2)
    }

    private func makeProjectsDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5h-tests-projects-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTranscript(
        in projects: URL,
        project: String,
        name: String,
        modifiedAt: Date
    ) throws {
        let directory = projects.appendingPathComponent(project, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        try Data("{}\n".utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: modifiedAt],
            ofItemAtPath: file.path
        )
    }

    private func removeDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
