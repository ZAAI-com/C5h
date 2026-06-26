import Foundation
import Testing
@testable import C5hCore

@Suite("HelperHealthEvaluator")
struct HelperHealthEvaluatorTests {
    private let now = Date(timeIntervalSince1970: 1_800)
    private let evaluator = HelperHealthEvaluator(staleAfterSeconds: 90)

    @Test
    func noHeartbeatIsNeverSeen() {
        let result = evaluator.evaluate(
            heartbeat: nil,
            now: now,
            isProcessAlive: { _ in true }
        )

        #expect(result.status == .neverSeen)
        #expect(result.lastSeenAt == nil)
        #expect(result.ageSeconds == nil)
        #expect(result.pid == nil)
    }

    @Test
    func freshHeartbeatWithAlivePIDIsRunning() {
        let result = evaluator.evaluate(
            heartbeat: HelperHeartbeatEvidence(
                lastSeenAt: now.addingTimeInterval(-30),
                pid: 123
            ),
            now: now,
            isProcessAlive: { pid in pid == 123 }
        )

        #expect(result.status == .running)
        #expect(result.ageSeconds == 30)
        #expect(result.pid == 123)
    }

    @Test
    func freshHeartbeatWithDeadPIDIsStopped() {
        let result = evaluator.evaluate(
            heartbeat: HelperHeartbeatEvidence(
                lastSeenAt: now.addingTimeInterval(-30),
                pid: 123
            ),
            now: now,
            isProcessAlive: { _ in false }
        )

        #expect(result.status == .stopped)
        #expect(result.ageSeconds == 30)
        #expect(result.pid == 123)
    }

    @Test
    func staleHeartbeatWithDeadPIDIsStale() {
        let result = evaluator.evaluate(
            heartbeat: HelperHeartbeatEvidence(
                lastSeenAt: now.addingTimeInterval(-91),
                pid: 123
            ),
            now: now,
            isProcessAlive: { _ in false }
        )

        #expect(result.status == .stale)
        #expect(result.ageSeconds == 91)
        #expect(result.pid == 123)
    }

    @Test
    func staleHeartbeatWithAlivePIDIsStale() {
        let result = evaluator.evaluate(
            heartbeat: HelperHeartbeatEvidence(
                lastSeenAt: now.addingTimeInterval(-91),
                pid: 123
            ),
            now: now,
            isProcessAlive: { _ in true }
        )

        #expect(result.status == .stale)
        #expect(result.ageSeconds == 91)
        #expect(result.pid == 123)
    }

    @Test
    func outdatedWhenReportedVersionDiffersFromExpected() {
        let result = evaluator.evaluate(
            heartbeat: HelperHeartbeatEvidence(
                lastSeenAt: now.addingTimeInterval(-30),
                pid: 123,
                version: "0.0.1+100"
            ),
            now: now,
            expectedVersion: "0.0.1+200",
            isProcessAlive: { _ in true }
        )

        #expect(result.status == .running)
        #expect(result.outdated)
    }

    @Test
    func notOutdatedWhenVersionsMatch() {
        let result = evaluator.evaluate(
            heartbeat: HelperHeartbeatEvidence(
                lastSeenAt: now.addingTimeInterval(-30),
                pid: 123,
                version: "0.0.1+200"
            ),
            now: now,
            expectedVersion: "0.0.1+200",
            isProcessAlive: { _ in true }
        )

        #expect(!result.outdated)
    }

    @Test
    func notOutdatedWhenExpectedVersionUnknown() {
        let result = evaluator.evaluate(
            heartbeat: HelperHeartbeatEvidence(
                lastSeenAt: now.addingTimeInterval(-30),
                pid: 123,
                version: "0.0.1+100"
            ),
            now: now,
            expectedVersion: nil,
            isProcessAlive: { _ in true }
        )

        #expect(!result.outdated)
    }

    @Test
    func freshHeartbeatWithoutPIDIsUnknown() {
        let result = evaluator.evaluate(
            heartbeat: HelperHeartbeatEvidence(
                lastSeenAt: now.addingTimeInterval(-30),
                pid: nil
            ),
            now: now,
            isProcessAlive: { _ in true }
        )

        #expect(result.status == .unknown)
        #expect(result.ageSeconds == 30)
        #expect(result.pid == nil)
    }
}
