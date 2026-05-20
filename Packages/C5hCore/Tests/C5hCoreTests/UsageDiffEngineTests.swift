import Foundation
import Testing
@testable import C5hCore

@Suite("UsageDiffEngine")
struct UsageDiffEngineTests {
    @Test("Diff orders snapshots by capturedAt")
    func order() {
        let a = NormalizedUsage(providerID: .claude, capturedAt: Date(timeIntervalSince1970: 100), messageCount: 5)
        let b = NormalizedUsage(providerID: .claude, capturedAt: Date(timeIntervalSince1970: 200), messageCount: 8)
        let d = UsageDiffEngine.diff(b, a)
        #expect(d?.messageDelta == 3)
        #expect(d?.from.timeIntervalSince1970 == 100)
        #expect(d?.to.timeIntervalSince1970 == 200)
    }

    @Test("Different providers do not diff")
    func crossProvider() {
        let a = NormalizedUsage(providerID: .claude, capturedAt: .now, messageCount: 1)
        let b = NormalizedUsage(providerID: .codex, capturedAt: .now, messageCount: 5)
        #expect(UsageDiffEngine.diff(a, b) == nil)
    }

    @Test("Inferred actual window is suppressed when c5hTriggered already covers the range")
    func suppressionWhenCovered() {
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let diff = UsageDiff(providerID: .claude, from: now, to: now.addingTimeInterval(3600), messageDelta: 50)
        let covering = ActualWindow(
            providerID: .claude,
            startAt: now,
            durationSeconds: 3600 * 5,
            source: .c5hTriggered,
            confidence: .exact
        )
        let inferred = UsageDiffEngine.inferActualWindow(from: diff, existingActuals: [covering])
        #expect(inferred == nil)
    }

    @Test("Below threshold yields no inference")
    func belowThreshold() {
        let now = Date()
        let diff = UsageDiff(providerID: .codex, from: now, to: now.addingTimeInterval(60), messageDelta: 1)
        let inferred = UsageDiffEngine.inferActualWindow(from: diff, existingActuals: [])
        #expect(inferred == nil)
    }

    @Test("Above threshold and uncovered creates detectedFromUsage estimated window")
    func detected() {
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let diff = UsageDiff(providerID: .codex, from: now, to: now.addingTimeInterval(3600), messageDelta: 25)
        let inferred = UsageDiffEngine.inferActualWindow(from: diff, existingActuals: [])
        #expect(inferred?.source == .detectedFromUsage)
        #expect(inferred?.confidence == .estimated)
    }
}
