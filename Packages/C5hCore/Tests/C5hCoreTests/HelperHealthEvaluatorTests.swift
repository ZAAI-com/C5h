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
                startedAt: now.addingTimeInterval(-60),
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
                startedAt: now.addingTimeInterval(-60),
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
                startedAt: now.addingTimeInterval(-120),
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
                startedAt: now.addingTimeInterval(-120),
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
    func outdatedWhenBinaryWasModifiedAfterHelperStarted() {
        let result = evaluator.evaluate(
            heartbeat: HelperHeartbeatEvidence(
                startedAt: now.addingTimeInterval(-60),
                lastSeenAt: now.addingTimeInterval(-30),
                pid: 123
            ),
            now: now,
            expectedBinaryModifiedAt: now.addingTimeInterval(-45),
            isProcessAlive: { _ in true }
        )

        #expect(result.status == .running)
        #expect(result.outdated)
    }

    @Test
    func notOutdatedWhenBinaryWasModifiedBeforeHelperStarted() {
        let result = evaluator.evaluate(
            heartbeat: HelperHeartbeatEvidence(
                startedAt: now.addingTimeInterval(-60),
                lastSeenAt: now.addingTimeInterval(-30),
                pid: 123
            ),
            now: now,
            expectedBinaryModifiedAt: now.addingTimeInterval(-90),
            isProcessAlive: { _ in true }
        )

        #expect(!result.outdated)
    }

    @Test
    func notOutdatedWhenBinaryModifiedAtMatchesHelperStart() {
        let result = evaluator.evaluate(
            heartbeat: HelperHeartbeatEvidence(
                startedAt: now.addingTimeInterval(-60),
                lastSeenAt: now.addingTimeInterval(-30),
                pid: 123
            ),
            now: now,
            expectedBinaryModifiedAt: now.addingTimeInterval(-60),
            isProcessAlive: { _ in true }
        )

        #expect(!result.outdated)
    }

    @Test
    func notOutdatedWhenExpectedBinaryModifiedAtIsUnknown() {
        let result = evaluator.evaluate(
            heartbeat: HelperHeartbeatEvidence(
                startedAt: now.addingTimeInterval(-60),
                lastSeenAt: now.addingTimeInterval(-30),
                pid: 123
            ),
            now: now,
            expectedBinaryModifiedAt: nil,
            isProcessAlive: { _ in true }
        )

        #expect(!result.outdated)
    }

    @Test
    func freshHeartbeatWithoutPIDIsUnknown() {
        let result = evaluator.evaluate(
            heartbeat: HelperHeartbeatEvidence(
                startedAt: now.addingTimeInterval(-60),
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
