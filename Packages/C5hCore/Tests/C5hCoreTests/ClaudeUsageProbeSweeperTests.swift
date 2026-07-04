import Foundation
import Testing
@testable import C5hCore

@Suite("ClaudeUsageProbeSweeper")
struct ClaudeUsageProbeSweeperTests {
    @Test("Matcher only targets orphaned C5h Claude usage probes")
    func matcherIsNarrow() {
        let usageProbe = ClaudeUsageProbeSweeper.ProcessCandidate(
            pid: 10,
            parentPID: 1,
            command: #"/opt/homebrew/bin/claude --settings {"statusLine":{"command":"echo C5H_RATE_LIMITS"}}"#
        )
        #expect(ClaudeUsageProbeSweeper.isOrphanedC5hClaudeUsageProbe(usageProbe))

        let activeParent = ClaudeUsageProbeSweeper.ProcessCandidate(
            pid: 11,
            parentPID: 100,
            command: usageProbe.command
        )
        #expect(ClaudeUsageProbeSweeper.isOrphanedC5hClaudeUsageProbe(activeParent) == false)

        let normalClaude = ClaudeUsageProbeSweeper.ProcessCandidate(
            pid: 12,
            parentPID: 1,
            command: "/opt/homebrew/bin/claude --print hello"
        )
        #expect(ClaudeUsageProbeSweeper.isOrphanedC5hClaudeUsageProbe(normalClaude) == false)

        let codex = ClaudeUsageProbeSweeper.ProcessCandidate(
            pid: 13,
            parentPID: 1,
            command: "/opt/homebrew/bin/codex --settings C5H_RATE_LIMITS"
        )
        #expect(ClaudeUsageProbeSweeper.isOrphanedC5hClaudeUsageProbe(codex) == false)
    }

    @Test("Sweeper only terminates matched processes")
    func sweeperTerminatesOnlyMatches() throws {
        let killed = KilledPIDs()
        let matched = ClaudeUsageProbeSweeper.ProcessCandidate(
            pid: 21,
            parentPID: 1,
            command: #"/Users/m/.local/bin/claude --settings {"statusLine":{"command":"C5H_RATE_LIMITS"}}"#
        )
        let unrelated = ClaudeUsageProbeSweeper.ProcessCandidate(
            pid: 22,
            parentPID: 1,
            command: "/Users/m/.local/bin/claude --version"
        )
        let sweeper = ClaudeUsageProbeSweeper(
            listProcesses: { [matched, unrelated] },
            terminate: { pid in
                killed.append(pid)
                return true
            }
        )

        let count = try sweeper.sweepOrphanedUsageProbes()
        #expect(count == 1)
        #expect(killed.values == [21])
    }
}

final class KilledPIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int32] = []

    var values: [Int32] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ pid: Int32) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(pid)
    }
}
