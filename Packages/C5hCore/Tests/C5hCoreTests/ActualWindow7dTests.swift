import Foundation
import Testing
@testable import C5hCore

@Suite("ActualWindow7d")
struct ActualWindow7dTests {
    @Test("remainingPercentage converts used to remaining and clamps")
    func remainingPercentageConversion() {
        #expect(ActualWindow7d.remainingPercentage(fromUsed: 0) == 100)
        #expect(ActualWindow7d.remainingPercentage(fromUsed: 45) == 55)
        #expect(ActualWindow7d.remainingPercentage(fromUsed: 100) == 0)
        #expect(ActualWindow7d.remainingPercentage(fromUsed: -5) == 100)
        #expect(ActualWindow7d.remainingPercentage(fromUsed: 150) == 0)
    }

    @Test("remainingPercentage property mirrors static helper")
    func remainingPercentageProperty() {
        let window = ActualWindow7d(
            providerID: .codex,
            startAt: .now,
            usedPercentage: 82,
            source: .detectedFromUsage,
            confidence: .estimated
        )
        #expect(window.remainingPercentage == 18)
    }
}
