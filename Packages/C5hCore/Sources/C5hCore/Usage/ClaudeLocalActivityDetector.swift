import Foundation

/// Read-only tripwire that detects local Claude Code activity by scanning the
/// session transcripts (`*.jsonl`) Claude Code writes under
/// `~/.claude/projects` for modification times after a reference date.
///
/// Used by `UsageCheckGate` for providers whose usage probe consumes quota
/// (`ProviderID.usageProbeConsumesQuota`): spawning Claude's REPL probe on an
/// idle account opens a fresh 5h window, so the probe may only run once
/// evidence says a window is already open. A fresh transcript is that
/// evidence: it means the user (or another local tool) already made a request.
///
/// The probe itself writes a transcript on every run (Claude Code records a
/// session for the probe's working directory), so that project directory is
/// excluded by default; without the exclusion each probe would count as
/// "activity" and re-arm the next probe forever.
public struct ClaudeLocalActivityDetector: Sendable {
    public let projectsDirectory: URL
    /// Encoded `~/.claude/projects` directory names whose transcripts never
    /// count as activity (the probe's own sessions).
    public let excludedProjectDirectoryNames: Set<String>
    /// Fail-closed scan bound: past this many transcript files the scan reports
    /// no activity. Skipping a probe only costs tracking, never quota.
    public let maxScannedFiles: Int

    private let scanCache: ClaudeLocalActivityScanCache

    public init(
        projectsDirectory: URL = Self.defaultProjectsDirectory,
        excludedProjectPaths: [URL] = Self.defaultExcludedProjectPaths,
        maxScannedFiles: Int = 50_000
    ) {
        self.projectsDirectory = projectsDirectory
        self.excludedProjectDirectoryNames = Set(
            excludedProjectPaths.map { Self.encodedProjectDirectoryName(forPath: $0.path) }
        )
        self.maxScannedFiles = maxScannedFiles
        self.scanCache = ClaudeLocalActivityScanCache()
    }

    public static let standard = ClaudeLocalActivityDetector()

    public static var defaultProjectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    public static var defaultExcludedProjectPaths: [URL] {
        guard let probeWorkingDirectory = ClaudeUsageCollector.probeWorkingDirectory() else {
            return []
        }
        return [probeWorkingDirectory]
    }

    /// Claude Code names each project directory after the session's working
    /// directory with every character outside [A-Za-z0-9] replaced by "-":
    /// "/Users/m/Library/Application Support/C5h" becomes
    /// "-Users-m-Library-Application-Support-C5h".
    public static func encodedProjectDirectoryName(forPath path: String) -> String {
        String(path.map { character in
            character.isASCII && (character.isLetter || character.isNumber) ? character : "-"
        })
    }

    /// True when any session `.jsonl` under `projectsDirectory` (outside the
    /// excluded project directories) was modified strictly after `reference`.
    /// `minimumRescanInterval` lets high-frequency callers reuse the latest
    /// complete walk; the cached modification date is compared with each
    /// caller's own reference, so an advancing boundary cannot reuse a stale
    /// Boolean. Returns false when the projects directory does not exist.
    public func hasActivity(
        since reference: Date,
        now: Date = .now,
        minimumRescanInterval: TimeInterval = 0
    ) async -> Bool {
        let projectsDirectory = projectsDirectory
        let excludedProjectDirectoryNames = excludedProjectDirectoryNames
        let maxScannedFiles = maxScannedFiles
        let result = await scanCache.result(
            now: now,
            minimumRescanInterval: minimumRescanInterval
        ) {
            Self.latestActivityBlocking(
                projectsDirectory: projectsDirectory,
                excludedProjectDirectoryNames: excludedProjectDirectoryNames,
                maxScannedFiles: maxScannedFiles
            )
        }
        guard let latestModificationDate = result.latestModificationDate else {
            return false
        }
        return latestModificationDate > reference
    }

    private static func latestActivityBlocking(
        projectsDirectory: URL,
        excludedProjectDirectoryNames: Set<String>,
        maxScannedFiles: Int
    ) -> ClaudeLocalActivityScanResult {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: projectsDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .completed(latestModificationDate: nil)
        }
        guard let projectDirectories = try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .completed(latestModificationDate: nil)
        }

        var scannedFileCount = 0
        var latestModificationDate: Date?
        for projectDirectory in projectDirectories {
            if excludedProjectDirectoryNames.contains(projectDirectory.lastPathComponent) {
                continue
            }
            // Deep enumeration: sessions nest transcripts in subdirectories
            // (e.g. subagents). Directory mtimes are not a valid pre-filter
            // because appends to an existing transcript do not bump the parent
            // directory, so every transcript file is checked.
            guard let enumerator = fileManager.enumerator(
                at: projectDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "jsonl" else { continue }
                scannedFileCount += 1
                if scannedFileCount > maxScannedFiles {
                    NSLog(
                        "ClaudeLocalActivityDetector: scan cap of %d files exceeded under %@; reporting no activity",
                        maxScannedFiles,
                        projectsDirectory.path
                    )
                    return .limitExceeded
                }
                guard let values = try? fileURL.resourceValues(
                    forKeys: [.contentModificationDateKey, .isRegularFileKey]
                ), values.isRegularFile == true,
                      let modificationDate = values.contentModificationDate else {
                    continue
                }
                if latestModificationDate.map({ modificationDate > $0 }) ?? true {
                    latestModificationDate = modificationDate
                }
            }
        }
        return .completed(latestModificationDate: latestModificationDate)
    }
}

enum ClaudeLocalActivityScanResult: Sendable, Equatable {
    case completed(latestModificationDate: Date?)
    case limitExceeded

    var latestModificationDate: Date? {
        switch self {
        case .completed(let latestModificationDate):
            latestModificationDate
        case .limitExceeded:
            nil
        }
    }
}

/// Serializes and coalesces filesystem walks for one detector configuration.
/// `ClaudeLocalActivityDetector.standard` is a value whose copies retain this
/// actor, so all gates in one process share a cache without global mutable state.
actor ClaudeLocalActivityScanCache {
    private struct CachedScan: Sendable {
        let scannedAt: Date
        let result: ClaudeLocalActivityScanResult
    }

    private var cachedScan: CachedScan?
    private var inFlight: Task<ClaudeLocalActivityScanResult, Never>?

    func result(
        now: Date,
        minimumRescanInterval: TimeInterval,
        scan: @escaping @Sendable () -> ClaudeLocalActivityScanResult
    ) async -> ClaudeLocalActivityScanResult {
        let interval = max(0, minimumRescanInterval)
        if let cachedScan {
            let age = now.timeIntervalSince(cachedScan.scannedAt)
            if age >= 0, age < interval {
                return cachedScan.result
            }
        }
        if let inFlight {
            return await inFlight.value
        }

        // Detach so the synchronous filesystem walk never occupies the caller's
        // actor executor. Concurrent callers await this same task.
        let task = Task.detached(priority: .utility, operation: scan)
        inFlight = task
        let result = await task.value
        cachedScan = CachedScan(scannedAt: now, result: result)
        inFlight = nil
        return result
    }
}
