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
    public var projectsDirectory: URL
    /// Encoded `~/.claude/projects` directory names whose transcripts never
    /// count as activity (the probe's own sessions).
    public var excludedProjectDirectoryNames: Set<String>
    /// Fail-closed scan bound: past this many transcript files the scan reports
    /// no activity. Skipping a probe only costs tracking, never quota.
    public var maxScannedFiles: Int

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
    /// Returns false when the projects directory does not exist.
    public func hasActivity(since reference: Date) async -> Bool {
        // Detach so the synchronous filesystem walk never occupies the caller's
        // actor executor.
        await Task.detached(priority: .utility) {
            hasActivityBlocking(since: reference)
        }.value
    }

    private func hasActivityBlocking(since reference: Date) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: projectsDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        guard let projectDirectories = try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        var scannedFileCount = 0
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
                    return false
                }
                guard let values = try? fileURL.resourceValues(
                    forKeys: [.contentModificationDateKey, .isRegularFileKey]
                ), values.isRegularFile == true,
                      let modificationDate = values.contentModificationDate else {
                    continue
                }
                if modificationDate > reference {
                    return true
                }
            }
        }
        return false
    }
}
