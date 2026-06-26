import Foundation

/// A detected change in a provider's reported quota window: the reset time moved
/// (or, for the weekly window, the used percentage dropped sharply) before the
/// previous window had elapsed. Surfaced as a neutral "reset detected" marker in
/// the UI, never tied to a subscription plan name.
public struct UsageResetEvent: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case fiveHour
        case sevenDay
    }

    public let providerID: ProviderID
    public let kind: Kind
    /// Capture time of the snapshot where the change was first observed.
    public let detectedAt: Date
    /// The reset end the provider reported before the change.
    public let previousResetEnd: Date
    /// The reset end the provider reported after the change. Equal to
    /// `previousResetEnd` for a same-end sharp-drop recalibration.
    public let newResetEnd: Date

    public var id: String {
        "\(providerID.rawValue)|\(kind.rawValue)|\(detectedAt.timeIntervalSince1970)"
    }

    public init(
        providerID: ProviderID,
        kind: Kind,
        detectedAt: Date,
        previousResetEnd: Date,
        newResetEnd: Date
    ) {
        self.providerID = providerID
        self.kind = kind
        self.detectedAt = detectedAt
        self.previousResetEnd = previousResetEnd
        self.newResetEnd = newResetEnd
    }
}

/// Detects quota-window reset events from a provider's sorted usage history. A
/// reset is a quota/window change (e.g. a Claude tier change), distinct from a
/// normal window rollover: the reported reset end moves while the previous
/// window is still open, or the weekly percentage drops sharply against an
/// unchanged reset end.
public enum UsageResetDetector {
    /// Reset-end changes smaller than this are treated as clock jitter, not a
    /// reset.
    static let endChangeTolerance: TimeInterval = 60
    /// Minimum absolute drop (in percentage points) for a same-end weekly
    /// recalibration to count as a reset.
    static let sevenDayDropPoints: Double = 20
    /// A same-end weekly drop only counts when the new value is at most this
    /// fraction of the previous value.
    static let sevenDayDropRatio: Double = 0.5

    public static func detect(in series: UsageHistorySeries) -> [UsageResetEvent] {
        let points = series.points
        guard points.count >= 2 else { return [] }

        var events: [UsageResetEvent] = []
        for index in 1..<points.count {
            let prev = points[index - 1]
            let curr = points[index]
            if let event = fiveHourReset(providerID: series.providerID, prev: prev, curr: curr) {
                events.append(event)
            }
            if let event = sevenDayReset(providerID: series.providerID, prev: prev, curr: curr) {
                events.append(event)
            }
        }
        return events
    }

    private static func fiveHourReset(
        providerID: ProviderID,
        prev: UsagePoint,
        curr: UsagePoint
    ) -> UsageResetEvent? {
        guard let prevEnd = prev.fiveHourResetsAt,
              let currEnd = curr.fiveHourResetsAt else { return nil }
        // The reset end must have moved meaningfully...
        guard abs(currEnd.timeIntervalSince(prevEnd)) > endChangeTolerance else { return nil }
        // ...while the previous window had not yet elapsed. A change observed at
        // or after the previous end is a normal rollover, not a reset.
        guard curr.capturedAt < prevEnd else { return nil }
        return UsageResetEvent(
            providerID: providerID,
            kind: .fiveHour,
            detectedAt: curr.capturedAt,
            previousResetEnd: prevEnd,
            newResetEnd: currEnd
        )
    }

    private static func sevenDayReset(
        providerID: ProviderID,
        prev: UsagePoint,
        curr: UsagePoint
    ) -> UsageResetEvent? {
        guard let prevEnd = prev.sevenDayResetsAt,
              let currEnd = curr.sevenDayResetsAt else { return nil }
        let endDelta = abs(currEnd.timeIntervalSince(prevEnd))

        // (a) The weekly end moved early.
        if endDelta > endChangeTolerance, curr.capturedAt < prevEnd {
            return UsageResetEvent(
                providerID: providerID,
                kind: .sevenDay,
                detectedAt: curr.capturedAt,
                previousResetEnd: prevEnd,
                newResetEnd: currEnd
            )
        }

        // (b) Same end, but the used percentage dropped sharply (recalibration).
        if endDelta <= endChangeTolerance,
           let prevPercent = prev.sevenDay,
           let currPercent = curr.sevenDay,
           prevPercent - currPercent >= sevenDayDropPoints,
           currPercent <= sevenDayDropRatio * prevPercent {
            return UsageResetEvent(
                providerID: providerID,
                kind: .sevenDay,
                detectedAt: curr.capturedAt,
                previousResetEnd: prevEnd,
                newResetEnd: currEnd
            )
        }

        return nil
    }
}
