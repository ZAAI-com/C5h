import Foundation
import Testing
@testable import C5hCore

@Suite("ClaudeLocalActivityDetector")
struct ClaudeLocalActivityDetectorTests {
    private let reference = Date(timeIntervalSince1970: 1_000_000)

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
