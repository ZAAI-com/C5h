import Foundation
import Testing
@testable import C5hCore

@Suite("ActualWindow7dDisplayResolver")
struct ActualWindow7dDisplayResolverTests {
    private static let base = Date(timeIntervalSince1970: 1_790_000_000)
    private static let day: TimeInterval = 86_400

    @Test("Non-overlapping windows keep their full span")
    func nonOverlappingUnchanged() throws {
        let first = weekly(startDay: 0, used: 80)
        let second = weekly(startDay: 8, used: 20)

        let segments = ActualWindow7dDisplayResolver.segments(for: [second, first])

        #expect(segments.map(\.id) == [first.id, second.id])
        #expect(segments.allSatisfy { $0.startAt == $0.window.startAt && $0.endAt == $0.window.endAt })
        #expect(segments.allSatisfy { !$0.isSuperseded })
    }

    @Test("An early successor clips its predecessor at the successor's start")
    func successorClipsPredecessor() throws {
        let first = weekly(startDay: 0, used: 100)
        let second = weekly(startDay: 2.5, used: 40)

        let segments = ActualWindow7dDisplayResolver.segments(for: [first, second])

        let firstSegment = try #require(segments.first { $0.id == first.id })
        let secondSegment = try #require(segments.first { $0.id == second.id })
        #expect(firstSegment.endAt == second.startAt)
        #expect(firstSegment.isSuperseded)
        #expect(firstSegment.durationSeconds == Int(2.5 * Self.day))
        #expect(secondSegment.endAt == second.endAt)
        #expect(!secondSegment.isSuperseded)
    }

    @Test("A superseded 0% window is dropped and the clip carries to the next survivor")
    func supersededZeroPercentDropped() throws {
        let used = weekly(startDay: 0, used: 100)
        // Legacy sliding prospective slots, minutes apart, never opened.
        let slotA = weekly(startDay: 1, used: 0)
        let slotB = weekly(startDay: 1 + 300 / Self.day, used: 0)
        let real = weekly(startDay: 2, used: 30)

        let segments = ActualWindow7dDisplayResolver.segments(for: [used, slotA, slotB, real])

        #expect(segments.map(\.id) == [used.id, real.id])
        let usedSegment = try #require(segments.first)
        #expect(usedSegment.endAt == real.startAt)
    }

    @Test("The latest window is kept even at 0%")
    func latestZeroPercentKept() throws {
        let first = weekly(startDay: 0, used: 90)
        let latest = weekly(startDay: 3, used: 0)

        let segments = ActualWindow7dDisplayResolver.segments(for: [first, latest])

        #expect(segments.map(\.id) == [first.id, latest.id])
        #expect(segments.last?.endAt == latest.endAt)
    }

    @Test("Duplicate starts collapse to one segment")
    func duplicateStartsCollapse() throws {
        let a = weekly(startDay: 0, used: 10)
        let b = weekly(startDay: 0, used: 20)

        let segments = ActualWindow7dDisplayResolver.segments(for: [a, b])

        #expect(segments.count == 1)
    }

    @Test("Providers are resolved independently")
    func providersIndependent() throws {
        let codex = weekly(startDay: 0, used: 50, providerID: .codex)
        let claude = weekly(startDay: 1, used: 50, providerID: .claude)

        let segments = ActualWindow7dDisplayResolver.segments(for: [codex, claude])

        #expect(segments.count == 2)
        #expect(segments.allSatisfy { !$0.isSuperseded })
    }

    private func weekly(
        startDay: Double,
        used: Double,
        providerID: ProviderID = .codex
    ) -> ActualWindow7d {
        ActualWindow7d(
            providerID: providerID,
            startAt: Self.base.addingTimeInterval(startDay * Self.day),
            usedPercentage: used,
            source: .detectedFromUsage,
            confidence: .estimated
        )
    }
}
