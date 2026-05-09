import Foundation

public struct UsageDiff: Sendable, Hashable {
    public let providerID: ProviderID
    public let from: Date
    public let to: Date
    public let messageDelta: Int
}

public enum UsageDiffEngine {
    public static func diff(_ a: NormalizedUsage, _ b: NormalizedUsage) -> UsageDiff? {
        guard a.providerID == b.providerID else { return nil }
        let earlier: NormalizedUsage
        let later: NormalizedUsage
        if a.capturedAt <= b.capturedAt { earlier = a; later = b }
        else { earlier = b; later = a }
        let delta = (later.messageCount ?? 0) - (earlier.messageCount ?? 0)
        return UsageDiff(
            providerID: a.providerID,
            from: earlier.capturedAt,
            to: later.capturedAt,
            messageDelta: delta
        )
    }

    /// Heuristic: if the message-count delta exceeds `threshold` between two
    /// snapshots and there is no c5hTriggered actual window already covering
    /// the interval, infer one.
    public static func inferActualWindow(
        from diff: UsageDiff,
        existingActuals: [ActualWindow],
        threshold: Int = 5
    ) -> ActualWindow? {
        guard diff.messageDelta >= threshold else { return nil }
        let interval = DateInterval(start: diff.from, end: diff.to)
        let alreadyCovered = existingActuals.contains { actual in
            actual.providerID == diff.providerID
                && actual.source == .c5hTriggered
                && DateInterval(start: actual.startAt, end: actual.endAt).intersects(interval)
        }
        guard !alreadyCovered else { return nil }
        return ActualWindow(
            providerID: diff.providerID,
            startAt: diff.from,
            durationSeconds: max(Int(diff.to.timeIntervalSince(diff.from)), 5 * 3600),
            source: .detectedFromUsage,
            confidence: .estimated
        )
    }
}
