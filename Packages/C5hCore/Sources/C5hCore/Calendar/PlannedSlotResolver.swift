import Foundation

/// Resolves where a dragged planned window may land on a provider's snap grid.
public enum PlannedSlotResolver {
    /// The allowed start closest to `candidate`, stepping by `stepSeconds`
    /// within `interval`. Resolving against the whole interval rather than
    /// only the positions the pointer has already passed means a drag over a
    /// blocking stretch (an actual window, a neighbouring plan, the past)
    /// jumps to the far side of it instead of freezing at its near edge.
    /// When a later and an earlier slot are equally close, the later one wins.
    /// Returns nil when the interval holds no allowed start at all.
    public static func nearestAllowedStart(
        near candidate: Date,
        in interval: DateInterval,
        stepSeconds: TimeInterval,
        isAllowed: (Date) -> Bool
    ) -> Date? {
        if isAllowed(candidate) { return candidate }
        guard stepSeconds > 0 else { return nil }
        let latestStart = interval.end.addingTimeInterval(-stepSeconds)
        // Alternate later/earlier so the first hit is the nearest one; the
        // interval's own length bounds the walk.
        let maxSteps = Int(interval.duration / stepSeconds) + 1
        for offset in 1...max(1, maxSteps) {
            let delta = Double(offset) * stepSeconds
            for signed in [candidate.addingTimeInterval(delta), candidate.addingTimeInterval(-delta)] {
                guard signed >= interval.start, signed <= latestStart else { continue }
                if isAllowed(signed) { return signed }
            }
        }
        return nil
    }
}
