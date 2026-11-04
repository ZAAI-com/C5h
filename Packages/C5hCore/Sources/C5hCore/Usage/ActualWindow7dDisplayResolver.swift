import Foundation

public struct ActualWindow7dDisplaySegment: Identifiable, Sendable, Hashable {
    public var id: UUID { window.id }
    public let window: ActualWindow7d
    public let startAt: Date
    public let endAt: Date

    public init(window: ActualWindow7d, startAt: Date? = nil, endAt: Date? = nil) {
        self.window = window
        self.startAt = startAt ?? window.startAt
        self.endAt = endAt ?? window.endAt
    }

    /// True when a later same-provider window started before this one's
    /// provider-reported end, so the displayed segment stops early.
    public var isSuperseded: Bool { endAt < window.endAt }

    public var durationSeconds: Int {
        max(0, Int(endAt.timeIntervalSince(startAt).rounded()))
    }
}

public enum ActualWindow7dDisplayResolver {
    /// Builds display-only weekly segments. Persisted rows stay full 7-day
    /// windows, but providers (Codex in particular) reset the weekly limit
    /// early, so a new window can start days before the previous one's stored
    /// end. Drawing raw rows would stack bands; instead each window's segment
    /// stops where the next same-provider window starts.
    ///
    /// A superseded window at 0% used never opened: it is a prospective slot
    /// that older builds persisted on every poll, so it is dropped rather than
    /// drawn as a sliver. The latest window is kept even at 0%.
    public static func segments(for windows: [ActualWindow7d]) -> [ActualWindow7dDisplaySegment] {
        var result: [ActualWindow7dDisplaySegment] = []
        for providerID in ProviderID.allCases {
            let sorted = windows
                .filter { $0.providerID == providerID }
                .sorted { $0.startAt < $1.startAt }
            // Walk newest first so a dropped window never clips its predecessor:
            // the clip carries over to the next surviving start.
            var nextStart: Date?
            var providerSegments: [ActualWindow7dDisplaySegment] = []
            for window in sorted.reversed() {
                let endAt = nextStart.map { min(window.endAt, $0) } ?? window.endAt
                if endAt < window.endAt, window.usedPercentage == 0 { continue }
                guard endAt > window.startAt else { continue }
                providerSegments.append(ActualWindow7dDisplaySegment(window: window, endAt: endAt))
                nextStart = window.startAt
            }
            result.append(contentsOf: providerSegments.reversed())
        }
        return result
    }
}
