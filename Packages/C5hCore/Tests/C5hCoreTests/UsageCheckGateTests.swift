import Foundation
import Testing
@testable import C5hCore

@Suite("UsageCheckGate")
struct UsageCheckGateTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("Always checks when idle-checking is enabled")
    func checksWhenIdleEnabled() async {
        let gate = makeGate(idleEnabled: true, hasActive: false, hasPending: false)
        #expect(await gate.shouldCheck(providerID: .claude, now: now))
    }

    @Test("Checks when idle-checking is off but an active window exists")
    func checksWithActiveWindow() async {
        let gate = makeGate(idleEnabled: false, hasActive: true, hasPending: false)
        #expect(await gate.shouldCheck(providerID: .claude, now: now))
    }

    @Test("Checks when idle-checking is off but a pending planned window exists")
    func checksWithPendingPlannedWindow() async {
        let gate = makeGate(idleEnabled: false, hasActive: false, hasPending: true)
        #expect(await gate.shouldCheck(providerID: .claude, now: now))
    }

    @Test("Passes now into planned-window check")
    func passesNowIntoPlannedWindowCheck() async {
        let gate = UsageCheckGate(
            isIdleCheckEnabled: { _ in false },
            hasActiveWindow: { _, _ in false },
            hasPendingPlannedWindow: { _, checkDate in checkDate == now }
        )
        #expect(await gate.shouldCheck(providerID: .claude, now: now))
    }

    @Test("Skips when idle-checking is off and there is no active or planned window")
    func skipsWhenIdleAndEmpty() async {
        let gate = makeGate(idleEnabled: false, hasActive: false, hasPending: false)
        #expect(await gate.shouldCheck(providerID: .claude, now: now) == false)
    }

    @Test("Gate is per provider: one provider's window does not enable another")
    func perProviderIsolation() async {
        // Idle checks off everywhere; only Claude has an active window.
        let gate = UsageCheckGate(
            isIdleCheckEnabled: { _ in false },
            hasActiveWindow: { providerID, _ in providerID == .claude },
            hasPendingPlannedWindow: { _, _ in false }
        )
        #expect(await gate.shouldCheck(providerID: .claude, now: now))
        #expect(await gate.shouldCheck(providerID: .codex, now: now) == false)
    }

    @Test("Fails closed: repo errors are treated as no window when idle checks are off")
    func failsClosedOnRepoError() async {
        struct Boom: Error {}
        let gate = UsageCheckGate(
            isIdleCheckEnabled: { _ in false },
            hasActiveWindow: { _, _ in throw Boom() },
            hasPendingPlannedWindow: { _, _ in throw Boom() }
        )
        #expect(await gate.shouldCheck(providerID: .claude, now: now) == false)
    }

    private func makeGate(idleEnabled: Bool, hasActive: Bool, hasPending: Bool) -> UsageCheckGate {
        UsageCheckGate(
            isIdleCheckEnabled: { _ in idleEnabled },
            hasActiveWindow: { _, _ in hasActive },
            hasPendingPlannedWindow: { _, _ in hasPending }
        )
    }
}
