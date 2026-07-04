import Foundation

public struct UsagePoint: Sendable, Hashable {
    public let capturedAt: Date
    public let fiveHour: Double?
    public let sevenDay: Double?
    /// The 5h window reset time the provider reported at `capturedAt`, when
    /// available. Used by `UsageResetDetector` to spot a window that reset early.
    public let fiveHourResetsAt: Date?
    /// True when `fiveHourResetsAt` represents an active, anchored provider
    /// window. Codex can report a synthetic "fresh slot" reset end when no 5h
    /// window has started; those points should render usage but not drive reset
    /// detection.
    public let hasActiveFiveHourWindow: Bool
    /// The 7d window reset time the provider reported at `capturedAt`, when
    /// available. Used by `UsageResetDetector` to spot a weekly reset.
    public let sevenDayResetsAt: Date?

    public init(
        capturedAt: Date,
        fiveHour: Double?,
        sevenDay: Double?,
        fiveHourResetsAt: Date? = nil,
        hasActiveFiveHourWindow: Bool = true,
        sevenDayResetsAt: Date? = nil
    ) {
        self.capturedAt = capturedAt
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.fiveHourResetsAt = fiveHourResetsAt
        self.hasActiveFiveHourWindow = hasActiveFiveHourWindow
        self.sevenDayResetsAt = sevenDayResetsAt
    }

    /// True when this point confirms `end` is the active 5h window: it reports
    /// an active window whose reset end is within `tolerance` of `end`. Shared
    /// by the display resolver's rolloff detection and window-scoped reading
    /// selection so both attribute points to windows the same way.
    public func confirmsActiveFiveHourWindow(
        endingAt end: Date,
        tolerance: TimeInterval
    ) -> Bool {
        hasActiveFiveHourWindow
            && (fiveHourResetsAt.map { abs($0.timeIntervalSince(end)) <= tolerance } ?? false)
    }
}

/// Sorted, in-memory time series of (5h%, 7d%) values for one provider, built
/// by parsing `UsageSnapshot.rawJSON`. UI uses this to render usage readings
/// at the time they were captured.
public struct UsageHistorySeries: Sendable, Hashable {
    public let providerID: ProviderID
    public let points: [UsagePoint]

    public init(providerID: ProviderID, snapshots: [UsageSnapshot]) {
        self.providerID = providerID
        let parsed = snapshots
            .filter { $0.providerID == providerID }
            .compactMap { Self.parse(snapshot: $0) }
            .sorted { $0.capturedAt < $1.capturedAt }
        self.points = Self.dedupeAdjacent(parsed)
    }

    public init(providerID: ProviderID, points: [UsagePoint]) {
        self.providerID = providerID
        self.points = Self.dedupeAdjacent(points.sorted { $0.capturedAt < $1.capturedAt })
    }

    public var latest: UsagePoint? { points.last }

    /// A copy of the series keeping only points that confirm the 5h window
    /// ending at `end` (see `UsagePoint.confirmsActiveFiveHourWindow`). The
    /// calendar scopes a block's readings this way so a snapshot belonging to
    /// an adjacent window with a different provider-reported reset end (e.g. a
    /// tier change re-anchored the window mid-flight) cannot leak into the
    /// block, even when its capture time falls inside the block's range.
    public func scoped(
        toFiveHourWindowEndingAt end: Date,
        tolerance: TimeInterval = ActualWindow5hDisplayResolver.resetEndTolerance
    ) -> UsageHistorySeries {
        UsageHistorySeries(
            providerID: providerID,
            points: points.filter {
                $0.confirmsActiveFiveHourWindow(endingAt: end, tolerance: tolerance)
            }
        )
    }

    /// 7d% from the latest point with `capturedAt <= time`. Returns nil when no
    /// such point exists (e.g., `time` is before any recorded snapshot). The
    /// series has no notion of "now"; callers that want to hide values for
    /// future windows should guard the call with their own `time > now` check.
    public func sevenDayPercent(at time: Date) -> (value: Double, asOf: Date)? {
        guard let point = lastPoint(atOrBefore: time), let value = point.sevenDay else { return nil }
        return (value, point.capturedAt)
    }

    /// Latest 5h% with its source capture time. Used by the box center.
    public func latestFiveHourPoint() -> (value: Double, asOf: Date)? {
        for point in points.reversed() {
            if let value = point.fiveHour {
                return (value, point.capturedAt)
            }
        }
        return nil
    }

    /// 5h% from the latest point with `capturedAt <= time` that has a 5h value,
    /// with its source capture time. Mirrors `sevenDayPercent(at:)` but, because
    /// 5h readings can be sparse, scans backward for the most recent point at or
    /// before `time` that actually carries a `fiveHour` value. Returns nil when
    /// no such point exists. The series has no notion of "now"; callers that want
    /// to hide values for future windows should guard with their own check.
    public func fiveHourPercent(at time: Date) -> (value: Double, asOf: Date)? {
        for point in points.reversed() where point.capturedAt <= time {
            if let value = point.fiveHour {
                return (value, point.capturedAt)
            }
        }
        return nil
    }

    /// Latest sample with a 5h reading inside `[lowerBound, time]`. The 7d
    /// value, when present, comes from the same snapshot so the UI renders one
    /// coherent usage row rather than mixing readings from different captures.
    public func usageReading(
        atOrBefore time: Date,
        notBefore lowerBound: Date
    ) -> (capturedAt: Date, fiveHour: Double, sevenDay: Double?)? {
        for point in points.reversed()
            where point.capturedAt <= time && point.capturedAt >= lowerBound {
            if let fiveHour = point.fiveHour {
                return (point.capturedAt, fiveHour, point.sevenDay)
            }
        }
        return nil
    }

    /// Earliest sample captured in `[start, start + seconds]`, used for the
    /// "opening" reading shown beside a window's start time. Unlike
    /// `usageReading(atOrBefore:notBefore:)`, this does not require a 5h value,
    /// because the opening annotation may show only 7d.
    public func openingReading(
        at start: Date,
        within seconds: TimeInterval
    ) -> (capturedAt: Date, fiveHour: Double?, sevenDay: Double?)? {
        let upper = start.addingTimeInterval(seconds)
        for point in points where point.capturedAt >= start && point.capturedAt <= upper {
            return (point.capturedAt, point.fiveHour, point.sevenDay)
        }
        return nil
    }

    /// Earliest sample in `[from, to]` whose 5h reading rounds to at least
    /// `threshold`, used to mark the moment a completed window hit its limit. The
    /// 7d value, when present, comes from the same snapshot.
    public func firstFiveHourReaching(
        _ threshold: Double,
        from lowerBound: Date,
        to upperBound: Date
    ) -> (capturedAt: Date, fiveHour: Double, sevenDay: Double?)? {
        for point in points where point.capturedAt >= lowerBound && point.capturedAt <= upperBound {
            if let fiveHour = point.fiveHour, fiveHour.rounded() >= threshold {
                return (point.capturedAt, fiveHour, point.sevenDay)
            }
        }
        return nil
    }

    /// The earliest sample of the trailing contiguous run of 5h readings in
    /// `[lowerBound, upperBound]` that all round to at least `threshold`.
    /// Returns nil when the latest in-range 5h reading rounds below
    /// `threshold`: after a same-window re-baseline (e.g. extra usage bought
    /// mid-window) the cap no longer holds, so callers unpin from the earlier
    /// capped moment and resume live readings. Contiguity is over samples that
    /// carry a 5h value; samples without one are skipped. The 7d value, when
    /// present, comes from the same snapshot.
    public func trailingFiveHourRunStart(
        reaching threshold: Double,
        from lowerBound: Date,
        to upperBound: Date
    ) -> (capturedAt: Date, fiveHour: Double, sevenDay: Double?)? {
        var runStart: (capturedAt: Date, fiveHour: Double, sevenDay: Double?)?
        for point in points.reversed()
            where point.capturedAt >= lowerBound && point.capturedAt <= upperBound {
            guard let fiveHour = point.fiveHour else { continue }
            guard fiveHour.rounded() >= threshold else { break }
            runStart = (point.capturedAt, fiveHour, point.sevenDay)
        }
        return runStart
    }

    private func lastPoint(atOrBefore time: Date) -> UsagePoint? {
        guard !points.isEmpty else { return nil }
        var lo = 0
        var hi = points.count - 1
        var bestIndex: Int? = nil
        while lo <= hi {
            let mid = (lo + hi) / 2
            if points[mid].capturedAt <= time {
                bestIndex = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return bestIndex.map { points[$0] }
    }

    private static func parse(snapshot: UsageSnapshot) -> UsagePoint? {
        switch snapshot.providerID {
        case .claude:
            guard let status = try? ClaudeUsageStatus.parsePayload(snapshot.rawJSON) else { return nil }
            return UsagePoint(
                capturedAt: snapshot.capturedAt,
                fiveHour: status.fiveHour.usedPercentage,
                sevenDay: status.sevenDay?.usedPercentage,
                fiveHourResetsAt: status.fiveHour.resetsAt,
                hasActiveFiveHourWindow: true,
                sevenDayResetsAt: status.sevenDay?.resetsAt
            )
        case .codex:
            guard let status = try? CodexUsageStatus.parseAny(
                snapshot.rawJSON,
                capturedAt: snapshot.capturedAt
            ) else { return nil }
            return UsagePoint(
                capturedAt: snapshot.capturedAt,
                fiveHour: status.primary.usedPercentage,
                sevenDay: status.secondary?.usedPercentage,
                fiveHourResetsAt: status.primary.resetsAt,
                hasActiveFiveHourWindow: status.hasActivePrimaryWindow,
                sevenDayResetsAt: status.secondary?.resetsAt
            )
        }
    }

    private static func dedupeAdjacent(_ points: [UsagePoint]) -> [UsagePoint] {
        var result: [UsagePoint] = []
        result.reserveCapacity(points.count)
        for point in points {
            if let last = result.last,
               last.capturedAt == point.capturedAt,
               last.fiveHour == point.fiveHour,
               last.sevenDay == point.sevenDay,
               last.fiveHourResetsAt == point.fiveHourResetsAt,
               last.hasActiveFiveHourWindow == point.hasActiveFiveHourWindow,
               last.sevenDayResetsAt == point.sevenDayResetsAt {
                continue
            }
            result.append(point)
        }
        return result
    }
}
