import Foundation
import Testing
@testable import C5hCore

@Suite("Models")
struct ModelsTests {
    @Test("PlannedWindow.endAt computes from startAt + durationSeconds")
    func plannedEndAt() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let window = PlannedWindow(
            providerID: .claude,
            startAt: start,
            durationSeconds: 5 * 3600
        )
        #expect(window.endAt.timeIntervalSince1970 == start.timeIntervalSince1970 + 5 * 3600)
    }

    @Test("ActualWindow defaults to 5h")
    func actualDefaultsTo5h() {
        let window = ActualWindow(
            providerID: .codex,
            startAt: .now,
            source: .c5hTriggered,
            confidence: .exact
        )
        #expect(window.durationSeconds == 5 * 3600)
    }

    @Test("Codable round-trip for PlannedWindow")
    func plannedCodable() throws {
        let original = PlannedWindow(
            providerID: .claude,
            startAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PlannedWindow.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.providerID == original.providerID)
    }

    @Test("ProviderID exposes display + executable names")
    func providerNames() {
        #expect(ProviderID.claude.displayName == "Claude")
        #expect(ProviderID.claude.executableName == "claude")
        #expect(ProviderID.codex.displayName == "Codex")
        #expect(ProviderID.codex.executableName == "codex")
    }
}
