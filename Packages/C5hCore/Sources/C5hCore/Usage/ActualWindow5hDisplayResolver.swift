import Foundation

public struct ActualWindow5hDisplaySegment: Identifiable, Sendable, Hashable {
    public var id: UUID { window.id }
    public let window: ActualWindow5h
    public let startAt: Date
    public let endAt: Date
    /// True only when `endAt` was clipped by a detected quota *reset* (a new
    /// window started early). False for a provider *rolloff* (the 5h limit went
    /// inactive / re-anchored with no reset event) and for unclipped ends, so the
    /// calendar shows the neutral reset glyph for resets only.
    public let marksResetEnd: Bool

    public init(
        window: ActualWindow5h,
        startAt: Date? = nil,
        endAt: Date? = nil,
        marksResetEnd: Bool = false
    ) {
        self.window = window
        self.startAt = startAt ?? window.startAt
        self.endAt = endAt ?? window.endAt
        self.marksResetEnd = marksResetEnd
    }

    public var durationSeconds: Int {
        max(0, Int(endAt.timeIntervalSince(startAt).rounded()))
    }
}

public enum ActualWindow5hDisplayResolver {
    public static let resetEndTolerance: TimeInterval = 60

    /// Builds display-only actual-window segments. Persisted windows remain full
    /// provider-reported rows, but the displayed segment is shortened in two
    /// cases:
    ///
    /// - **Reset:** a detected 5h reset starts a new window before an earlier
    ///   same-provider window ended, so the earlier segment stops at the reset
    ///   window's start (marked with the neutral reset glyph).
    /// - **Rolloff:** the provider's usage history shows a window's 5h limit went
    ///   inactive (a synthetic "fresh slot") or re-anchored to a different reset
    ///   end before its stored end, with no reset event. The segment stops at the
    ///   first observation of the rolloff (no glyph: this is not a quota reset).
    public static func segments(
        for windows: [ActualWindow5h],
        resetEvents: [UsageResetEvent],
        histories: [ProviderID: UsageHistorySeries] = [:],
        resetEndTolerance: TimeInterval = Self.resetEndTolerance
    ) -> [ActualWindow5hDisplaySegment] {
        guard !windows.isEmpty else { return [] }

        var displayEndByWindowID = Dictionary(
            uniqueKeysWithValues: windows.map { ($0.id, $0.endAt) }
        )
        var marksResetByWindowID = Dictionary(
            uniqueKeysWithValues: windows.map { ($0.id, false) }
        )

        // Reset pass: an earlier window stops where a detected reset's new window
        // begins. Carries the reset glyph.
        for event in resetEvents where event.kind == .fiveHour {
            guard let resetWindow = resetWindow(
                for: event,
                in: windows,
                tolerance: resetEndTolerance
            ) else { continue }
            let boundary = resetWindow.startAt

            for window in windows where window.providerID == event.providerID && window.id != resetWindow.id {
                let currentEnd = displayEndByWindowID[window.id] ?? window.endAt
                guard window.startAt < boundary, boundary < currentEnd else { continue }
                displayEndByWindowID[window.id] = boundary
                marksResetByWindowID[window.id] = true
            }
        }

        // Rolloff pass: the provider's history shows the window's limit went
        // inactive before its stored end, with no reset event. Not a quota reset,
        // so no glyph. A rolloff within tolerance of an existing reset clip is the
        // same boundary observed two ways (e.g. a Claude early reset): keep the
        // reset boundary and glyph.
        for window in windows {
            guard let rolloff = rolloffEnd(
                for: window,
                history: histories[window.providerID],
                tolerance: resetEndTolerance
            ) else { continue }
            let currentEnd = displayEndByWindowID[window.id] ?? window.endAt
            guard rolloff < currentEnd else { continue }
            let sameAsResetClip = (marksResetByWindowID[window.id] == true)
                && currentEnd.timeIntervalSince(rolloff) <= resetEndTolerance
            guard !sameAsResetClip else { continue }
            displayEndByWindowID[window.id] = rolloff
            marksResetByWindowID[window.id] = false
        }

        return windows.compactMap { window in
            segment(
                for: window,
                endAt: displayEndByWindowID[window.id] ?? window.endAt,
                marksResetEnd: marksResetByWindowID[window.id] ?? false
            )
        }
    }

    /// The capture time at which `window`'s 5h limit was first observed to roll
    /// off (go inactive or re-anchor to a different reset end) after having been
    /// the confirmed active window. nil when there is no confirming history point
    /// (don't over-clip on missing data) or no later in-window point (the window
    /// is still live, or ended naturally).
    private static func rolloffEnd(
        for window: ActualWindow5h,
        history: UsageHistorySeries?,
        tolerance: TimeInterval
    ) -> Date? {
        guard let points = history?.points, !points.isEmpty else { return nil }
        let end = window.endAt
        // The latest in-window point that confirms this is the active 5h window.
        guard let confirmIndex = points.lastIndex(where: {
            $0.capturedAt < end
                && $0.confirmsActiveFiveHourWindow(endingAt: end, tolerance: tolerance)
        }) else {
            return nil
        }
        let confirmedAt = points[confirmIndex].capturedAt
        // Because that was the latest confirming point, the first later point
        // still before the window's natural end is necessarily non-confirming:
        // the moment the window rolled off.
        let rolledOffAt = points.first {
            $0.capturedAt > confirmedAt && $0.capturedAt < end
        }?.capturedAt
        return rolledOffAt
    }

    private static func resetWindow(
        for event: UsageResetEvent,
        in windows: [ActualWindow5h],
        tolerance: TimeInterval
    ) -> ActualWindow5h? {
        windows
            .filter {
                $0.providerID == event.providerID
                    && abs($0.endAt.timeIntervalSince(event.newResetEnd)) <= tolerance
            }
            .sorted {
                let lhsDelta = abs($0.endAt.timeIntervalSince(event.newResetEnd))
                let rhsDelta = abs($1.endAt.timeIntervalSince(event.newResetEnd))
                if lhsDelta != rhsDelta { return lhsDelta < rhsDelta }
                return $0.startAt < $1.startAt
            }
            .first
    }

    private static func segment(
        for window: ActualWindow5h,
        endAt: Date,
        marksResetEnd: Bool
    ) -> ActualWindow5hDisplaySegment? {
        guard endAt > window.startAt else { return nil }
        return ActualWindow5hDisplaySegment(
            window: window,
            endAt: endAt,
            marksResetEnd: marksResetEnd
        )
    }
}
