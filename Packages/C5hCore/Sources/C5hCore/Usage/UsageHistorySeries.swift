import Foundation

public struct UsagePoint: Sendable, Hashable {
    public let capturedAt: Date
    public let fiveHour: Double?
    public let sevenDay: Double?

    public init(capturedAt: Date, fiveHour: Double?, sevenDay: Double?) {
        self.capturedAt = capturedAt
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }
}

/// Sorted, in-memory time series of (5h%, 7d%) values for one provider, built
/// by parsing `UsageSnapshot.rawJSON`. UI uses this to render "7d% at time T"
/// on each calendar window box and "latest 5h%" in the box center.
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
                sevenDay: status.sevenDay?.usedPercentage
            )
        case .codex:
            guard let status = try? CodexUsageStatus.parseAny(
                snapshot.rawJSON,
                capturedAt: snapshot.capturedAt
            ) else { return nil }
            return UsagePoint(
                capturedAt: snapshot.capturedAt,
                fiveHour: status.primary.usedPercentage,
                sevenDay: status.secondary?.usedPercentage
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
               last.sevenDay == point.sevenDay {
                continue
            }
            result.append(point)
        }
        return result
    }
}
