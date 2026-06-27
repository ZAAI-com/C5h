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
        // The clipped earlier segment carries the reset glyph; the new window's
        // own (unclipped) end does not.
        #expect(firstSegment.marksResetEnd == true)
        #expect(resetSegment.startAt == reset.startAt)
        #expect(resetSegment.endAt == reset.endAt)
        #expect(resetSegment.marksResetEnd == false)
    }

    @Test("Rolloff to a synthetic fresh slot clips a stale window without a glyph")
    func rolloffClipsStaleCodexWindowToFreshSlot() throws {
        // Mirrors the reported bug: a Codex 5h window detected earlier (07:30 →
        // 12:30) whose limit later rolls off to a synthetic "fresh slot" at 09:46,
        // with no reset event. The segment must stop at the rolloff, not 12:30.
        let window = actualWindow(providerID: .codex, startHour: 7.5)
        let confirming = point(hour: 8, fiveHour: 40, sevenDay: 90, resetsAt: window.endAt, active: true)
        let freshSlotAt = referenceDay.addingTimeInterval(9.766 * 3_600)
        let freshSlot = point(
            at: freshSlotAt,
            fiveHour: 1,
            sevenDay: 100,
            resetsAt: freshSlotAt.addingTimeInterval(5 * 3_600),
            active: false
        )
        let series = UsageHistorySeries(providerID: .codex, points: [confirming, freshSlot])

        let segments = ActualWindow5hDisplayResolver.segments(
            for: [window],
            resetEvents: [],
            histories: [.codex: series]
        )

        let segment = try #require(segments.first { $0.id == window.id })
        #expect(segment.startAt == window.startAt)
        #expect(segment.endAt == freshSlotAt)
        #expect(segment.marksResetEnd == false)
    }

    @Test("Rolloff is not applied without a confirming history point")
    func rolloffWithoutConfirmingPointDoesNotClip() throws {
        // Only synthetic points (never an active, matching window): we cannot
        // prove a rolloff, so the window keeps its full provider-reported end.
        let window = actualWindow(providerID: .codex, startHour: 7.5)
        let p1 = point(hour: 8, fiveHour: 1, resetsAt: referenceDay.addingTimeInterval(13 * 3_600), active: false)
        let p2 = point(hour: 9, fiveHour: 1, resetsAt: referenceDay.addingTimeInterval(14 * 3_600), active: false)
        let series = UsageHistorySeries(providerID: .codex, points: [p1, p2])

        let segments = ActualWindow5hDisplayResolver.segments(
            for: [window],
            resetEvents: [],
            histories: [.codex: series]
        )

        let segment = try #require(segments.first { $0.id == window.id })
        #expect(segment.endAt == window.endAt)
        #expect(segment.marksResetEnd == false)
    }

    @Test("A still-live window (latest point still confirms) is not clipped")
    func rolloffDoesNotClipStillLiveWindow() throws {
        let window = actualWindow(providerID: .codex, startHour: 7.5)
        let p1 = point(hour: 8, fiveHour: 30, resetsAt: window.endAt, active: true)
        let p2 = point(hour: 9, fiveHour: 50, resetsAt: window.endAt, active: true)
        let series = UsageHistorySeries(providerID: .codex, points: [p1, p2])

        let segments = ActualWindow5hDisplayResolver.segments(
            for: [window],
            resetEvents: [],
            histories: [.codex: series]
        )

        let segment = try #require(segments.first { $0.id == window.id })
        #expect(segment.endAt == window.endAt)
    }

    @Test("Claude window with a stable reset end is never clipped by rolloff")
    func claudeWindowWithStableResetIsNotClipped() throws {
        // Claude points always report an active window with the same reset end
        // while the window is open, so the rolloff rule is a no-op for Claude.
        let window = actualWindow(providerID: .claude, startHour: 7.5)
        let p1 = point(hour: 8, fiveHour: 30, resetsAt: window.endAt, active: true)
        let p2 = point(hour: 10, fiveHour: 60, resetsAt: window.endAt, active: true)
        let series = UsageHistorySeries(providerID: .claude, points: [p1, p2])

        let segments = ActualWindow5hDisplayResolver.segments(
            for: [window],
            resetEvents: [],
            histories: [.claude: series]
        )

        let segment = try #require(segments.first { $0.id == window.id })
        #expect(segment.endAt == window.endAt)
        #expect(segment.marksResetEnd == false)
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

    private func point(
        hour: Double,
        fiveHour: Double?,
        sevenDay: Double? = nil,
        resetsAt: Date?,
        active: Bool
    ) -> UsagePoint {
        point(
            at: referenceDay.addingTimeInterval(hour * 3_600),
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            resetsAt: resetsAt,
            active: active
        )
    }

    private func point(
        at capturedAt: Date,
        fiveHour: Double?,
        sevenDay: Double? = nil,
        resetsAt: Date?,
        active: Bool
    ) -> UsagePoint {
        UsagePoint(
            capturedAt: capturedAt,
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            fiveHourResetsAt: resetsAt,
            hasActiveFiveHourWindow: active,
            sevenDayResetsAt: nil
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
