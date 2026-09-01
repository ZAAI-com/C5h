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

/// Which quota limits a provider explicitly reported in a usage snapshot.
public struct ProviderUsageLimits: Sendable, Hashable {
    public let hasFiveHourLimit: Bool
    public let hasWeeklyLimit: Bool

    public var isWeeklyOnly: Bool { hasWeeklyLimit && !hasFiveHourLimit }

    public init(hasFiveHourLimit: Bool, hasWeeklyLimit: Bool) {
        self.hasFiveHourLimit = hasFiveHourLimit
        self.hasWeeklyLimit = hasWeeklyLimit
    }

    public static func from(snapshot: UsageSnapshot) -> ProviderUsageLimits? {
        switch snapshot.providerID {
        case .claude:
            guard let status = try? ClaudeUsageStatus.parsePayload(snapshot.rawJSON) else { return nil }
            return ProviderUsageLimits(
                hasFiveHourLimit: true,
                hasWeeklyLimit: status.sevenDay != nil
            )
        case .codex:
            guard let status = try? CodexUsageStatus.parseAny(
                snapshot.rawJSON,
                capturedAt: snapshot.capturedAt
            ) else { return nil }
            return ProviderUsageLimits(
                hasFiveHourLimit: status.hasFiveHourClassLimit,
                hasWeeklyLimit: status.hasWeeklyClassLimit
            )
        }
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

    public func scoped(
        toWeeklyWindowEndingAt end: Date,
        tolerance: TimeInterval = ActualWindow5hDisplayResolver.resetEndTolerance
    ) -> UsageHistorySeries {
        UsageHistorySeries(
            providerID: providerID,
            points: points.filter {
                $0.sevenDayResetsAt.map { abs($0.timeIntervalSince(end)) <= tolerance } ?? false
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

    /// The real 7d readings captured within `interval`, each at the time its usage
    /// command actually ran. Consecutive samples with the same rounded percentage
    /// collapse to one entry (kept at the capture where that value first appeared),
    /// so a value polled every few minutes but unchanged does not produce a stack of
    /// identical rows. Points exist only at real capture times, so passing an
    /// interval ending at `now` yields a past-only list: the calendar draws one row
    /// per returned reading instead of a synthetic time grid, and never shows a value
    /// at a time it was not measured.
    public func weeklyReadings(in interval: DateInterval) -> [(capturedAt: Date, used: Double)] {
        var readings: [(capturedAt: Date, used: Double)] = []
        var lastRoundedPercent: Int?
        for point in points where interval.contains(point.capturedAt) {
            guard let used = point.sevenDay else { continue }
            let rounded = Int(used.rounded())
            if rounded == lastRoundedPercent { continue }
            lastRoundedPercent = rounded
            readings.append((point.capturedAt, used))
        }
        return readings
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

    /// Earliest sample captured in `[start, start + seconds]` with a 7d reading,
    /// falling back to the latest point at or before `start` when none fall in
    /// the opening window. Used for the carry-in reading at the top of a weekly
    /// calendar block.
    public func weeklyOpeningReading(
        at start: Date,
        within seconds: TimeInterval
    ) -> (capturedAt: Date, used: Double)? {
        let upper = start.addingTimeInterval(seconds)
        for point in points where point.capturedAt >= start && point.capturedAt <= upper {
            if let sevenDay = point.sevenDay {
                return (point.capturedAt, sevenDay)
            }
        }
        for point in points.reversed() where point.capturedAt <= start {
            if let sevenDay = point.sevenDay {
                return (point.capturedAt, sevenDay)
            }
        }
        return nil
    }

    /// Latest in-day 7d reading whose used value differs from `carryInUsed`.
    /// Returns nil when every sample on `day` matches the carry-in or lacks 7d.
    public func latestDistinctWeeklyReading(
        on day: Date,
        carryInUsed: Double?,
        calendar: Calendar = .current
    ) -> (capturedAt: Date, used: Double)? {
        let dayBounds = CalendarPositioning.dayInterval(for: day, calendar: calendar)
        var latest: (capturedAt: Date, used: Double)?
        for point in points
            where point.capturedAt >= dayBounds.start && point.capturedAt < dayBounds.end {
            guard let sevenDay = point.sevenDay else { continue }
            if let carryInUsed, sevenDay == carryInUsed { continue }
            latest = (point.capturedAt, sevenDay)
        }
        return latest
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
                // Claude slides an unopened 5h slot forward every 10 minutes
                // while idle. Marking those points inactive keeps them out of
                // reset detection, which would otherwise read each slide as a
                // quota reset and clip real windows around it.
                hasActiveFiveHourWindow: !status.isProspectiveFiveHourSlot(
                    capturedAt: snapshot.capturedAt
                ),
                sevenDayResetsAt: status.sevenDay?.resetsAt
            )
        case .codex:
            guard let status = try? CodexUsageStatus.parseAny(
                snapshot.rawJSON,
                capturedAt: snapshot.capturedAt
            ) else { return nil }
            return UsagePoint(
                capturedAt: snapshot.capturedAt,
                fiveHour: status.fiveHourUsedPercentage,
                sevenDay: status.weeklyUsedPercentage,
                fiveHourResetsAt: status.fiveHourResetsAt,
                hasActiveFiveHourWindow: status.hasActiveFiveHourWindow,
                sevenDayResetsAt: status.weeklyResetsAt
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
