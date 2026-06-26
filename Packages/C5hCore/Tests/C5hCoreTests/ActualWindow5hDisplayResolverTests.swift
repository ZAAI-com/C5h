import Foundation
import Testing
@testable import C5hCore

@Suite("ActualWindow5hDisplayResolver")
struct ActualWindow5hDisplayResolverTests {
    @Test("Early reset clips prior window at reset boundary")
    func earlyResetClipsPriorWindow() throws {
        let first = actualWindow(startHour: 11.5)
        let reset = actualWindow(startHour: 13 + 40.0 / 60.0)
        let event = resetEvent(previousEnd: first.endAt, newEnd: reset.endAt, detectedAt: reset.startAt)

        let segments = ActualWindow5hDisplayResolver.segments(
            for: [first, reset],
            resetEvents: [event]
        )

        let firstSegment = try #require(segments.first { $0.id == first.id })
        let resetSegment = try #require(segments.first { $0.id == reset.id })
        #expect(firstSegment.startAt == first.startAt)
        #expect(firstSegment.endAt == reset.startAt)
        #expect(firstSegment.durationSeconds == 7_800)
        #expect(resetSegment.startAt == reset.startAt)
        #expect(resetSegment.endAt == reset.endAt)
    }

    @Test("Overlapping windows without reset event are unchanged")
    func overlappingWindowsWithoutResetStayFullLength() throws {
        let first = actualWindow(startHour: 11.5)
        let overlapping = actualWindow(startHour: 13 + 40.0 / 60.0)

        let segments = ActualWindow5hDisplayResolver.segments(
            for: [first, overlapping],
            resetEvents: []
        )

        let firstSegment = try #require(segments.first { $0.id == first.id })
        let overlappingSegment = try #require(segments.first { $0.id == overlapping.id })
        #expect(firstSegment.endAt == first.endAt)
        #expect(overlappingSegment.endAt == overlapping.endAt)
    }

    @Test("Reset event without matching reset window is ignored")
    func resetWithoutMatchingWindowIsIgnored() throws {
        let first = actualWindow(startHour: 11.5)
        let overlapping = actualWindow(startHour: 13 + 40.0 / 60.0)
        let unmatchedEnd = overlapping.endAt.addingTimeInterval(5 * 60)
        let event = resetEvent(previousEnd: first.endAt, newEnd: unmatchedEnd, detectedAt: overlapping.startAt)

        let segments = ActualWindow5hDisplayResolver.segments(
            for: [first, overlapping],
            resetEvents: [event]
        )

        let firstSegment = try #require(segments.first { $0.id == first.id })
        #expect(firstSegment.endAt == first.endAt)
    }

    @Test("Touching normal rollover windows are unchanged")
    func touchingRolloverWindowsStayFullLength() throws {
        let first = actualWindow(startHour: 11.5)
        let next = actualWindow(startHour: 16.5)

        let segments = ActualWindow5hDisplayResolver.segments(
            for: [first, next],
            resetEvents: []
        )

        let firstSegment = try #require(segments.first { $0.id == first.id })
        let nextSegment = try #require(segments.first { $0.id == next.id })
        #expect(firstSegment.endAt == first.endAt)
        #expect(nextSegment.startAt == next.startAt)
        #expect(nextSegment.endAt == next.endAt)
    }

    @Test("Reset event only clips matching provider windows")
    func resetOnlyClipsMatchingProvider() throws {
        let claudeFirst = actualWindow(providerID: .claude, startHour: 11.5)
        let claudeReset = actualWindow(providerID: .claude, startHour: 13 + 40.0 / 60.0)
        let codexOverlap = actualWindow(providerID: .codex, startHour: 11.75)
        let event = resetEvent(
            providerID: .claude,
            previousEnd: claudeFirst.endAt,
            newEnd: claudeReset.endAt,
            detectedAt: claudeReset.startAt
        )

        let segments = ActualWindow5hDisplayResolver.segments(
            for: [claudeFirst, claudeReset, codexOverlap],
            resetEvents: [event]
        )

        let claudeSegment = try #require(segments.first { $0.id == claudeFirst.id })
        let codexSegment = try #require(segments.first { $0.id == codexOverlap.id })
        #expect(claudeSegment.endAt == claudeReset.startAt)
        #expect(codexSegment.endAt == codexOverlap.endAt)
    }

    private func actualWindow(
        providerID: ProviderID = .claude,
        startHour: Double
    ) -> ActualWindow5h {
        ActualWindow5h(
            providerID: providerID,
            startAt: referenceDay.addingTimeInterval(startHour * 3_600),
            durationSeconds: 5 * 3_600,
            source: .detectedFromUsage,
            confidence: .estimated
        )
    }

    private func resetEvent(
        providerID: ProviderID = .claude,
        previousEnd: Date,
        newEnd: Date,
        detectedAt: Date
    ) -> UsageResetEvent {
        UsageResetEvent(
            providerID: providerID,
            kind: .fiveHour,
            detectedAt: detectedAt,
            previousResetEnd: previousEnd,
            newResetEnd: newEnd
        )
    }

    private var referenceDay: Date {
        Date(timeIntervalSince1970: 1_800_000_000)
    }
}
