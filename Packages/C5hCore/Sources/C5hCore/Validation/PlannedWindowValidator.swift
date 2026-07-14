import Foundation

/// Advisory raised when a candidate planned window starts inside the previous
/// same-provider window's chained slot. Providers chain a new 5h window onto
/// the old one's end whenever the account shows activity in that stretch, so a
/// start with `0 < gap < windowLength` after the previous end may land in a
/// window that effectively ends at `previousWindowEnd + windowLength`, shorter
/// than the full window the user planned for. Advisory only: the boundary can
/// also decay (a fully idle account re-anchors fresh), and a short gap is
/// sometimes intentional.
public struct PlannedWindowChainRisk: Sendable, Hashable {
    public var previousWindowEnd: Date
    public var projectedEffectiveEnd: Date
    public var shortfallSeconds: Int
    /// Starts that avoid the risk: back-to-back at the previous end, or at the
    /// chained slot's end for a fresh full-length window.
    public var suggestedStarts: [Date]

    public init(
        previousWindowEnd: Date,
        projectedEffectiveEnd: Date,
        shortfallSeconds: Int,
        suggestedStarts: [Date]
    ) {
        self.previousWindowEnd = previousWindowEnd
        self.projectedEffectiveEnd = projectedEffectiveEnd
        self.shortfallSeconds = shortfallSeconds
        self.suggestedStarts = suggestedStarts
    }
}

public struct PlannedWindowValidationResult: Sendable, Hashable {
    public var conflictingWindowIDs: [UUID]
    public var chainRisk: PlannedWindowChainRisk?
    public var hasConflict: Bool { !conflictingWindowIDs.isEmpty }

    public init(
        conflictingWindowIDs: [UUID],
        chainRisk: PlannedWindowChainRisk? = nil
    ) {
        self.conflictingWindowIDs = conflictingWindowIDs
        self.chainRisk = chainRisk
    }
}

public enum PlannedWindowValidator {
    public static func validate(
        candidate: PlannedWindow,
        against existing: [PlannedWindow]
    ) -> PlannedWindowValidationResult {
        guard candidate.durationSeconds >= 0 else {
            return PlannedWindowValidationResult(conflictingWindowIDs: [])
        }
        // Half-open `[start, end)` overlap, matching PlannedWindowRepository's
        // overlap SQL and CalendarPositioning.packLanes: touching boundaries
        // (one window's start == another's end) are back-to-back, not conflicts.
        let conflicts = existing.filter { other in
            guard other.id != candidate.id else { return false }
            guard other.providerID == candidate.providerID else { return false }
            guard other.durationSeconds >= 0 else { return false }
            return candidate.startAt < other.endAt && other.startAt < candidate.endAt
        }
        return PlannedWindowValidationResult(
            conflictingWindowIDs: conflicts.map { $0.id }
        )
    }

    public static func validate(
        candidate: PlannedWindow,
        against existing: [PlannedWindow],
        actualWindows: [ActualWindow5h]
    ) -> PlannedWindowValidationResult {
        let plannedResult = validate(candidate: candidate, against: existing)
        guard candidate.durationSeconds >= 0 else {
            return plannedResult
        }
        // Any same-provider actual window that overlaps the candidate is a
        // conflict, regardless of whether it is in the past, in progress, or in
        // the future. Half-open `[start, end)` overlap, matching the planned-only
        // overload: touching boundaries are back-to-back, not conflicts.
        let actualConflicts = actualWindows.filter { other in
            guard other.providerID == candidate.providerID else { return false }
            guard other.durationSeconds >= 0 else { return false }
            return candidate.startAt < other.endAt && other.startAt < candidate.endAt
        }
        return PlannedWindowValidationResult(
            conflictingWindowIDs: plannedResult.conflictingWindowIDs + actualConflicts.map { $0.id },
            chainRisk: chainRisk(
                candidate: candidate,
                against: existing,
                actualWindows: actualWindows
            )
        )
    }

    /// Detects when `candidate` starts inside the previous same-provider
    /// window's chained slot: `0 < startAt - previousWindowEnd < windowLength`.
    /// The previous end is the latest end at or before the candidate's start,
    /// from provider-anchored actual windows and earlier scheduled planned
    /// windows (their projected ends: a scheduled earlier window will open a
    /// real block; a manual actual window or a draft plan will not, so both are
    /// excluded). Gap 0 (back-to-back) and gaps of a full window length or more
    /// are safe. Stale history is self-limiting: anything ending more than a
    /// window length before the start produces no advisory.
    public static func chainRisk(
        candidate: PlannedWindow,
        against existing: [PlannedWindow],
        actualWindows: [ActualWindow5h]
    ) -> PlannedWindowChainRisk? {
        guard candidate.durationSeconds > 0 else { return nil }
        let windowLength = TimeInterval(candidate.durationSeconds)

        var previousEnds = actualWindows
            .filter {
                $0.providerID == candidate.providerID
                    && $0.durationSeconds >= 0
                    && $0.hasProviderAnchoredUsageWindow
            }
            .map(\.endAt)
        previousEnds += existing
            .filter { other in
                other.id != candidate.id
                    && other.providerID == candidate.providerID
                    && other.status == .scheduled
                    && other.durationSeconds >= 0
                    && other.startAt < candidate.startAt
            }
            .map(\.endAt)

        guard let previousEnd = previousEnds.filter({ $0 <= candidate.startAt }).max() else {
            return nil
        }
        let gap = candidate.startAt.timeIntervalSince(previousEnd)
        guard gap > 0, gap < windowLength else { return nil }

        let projectedEffectiveEnd = previousEnd.addingTimeInterval(windowLength)
        return PlannedWindowChainRisk(
            previousWindowEnd: previousEnd,
            projectedEffectiveEnd: projectedEffectiveEnd,
            shortfallSeconds: Int(candidate.endAt.timeIntervalSince(projectedEffectiveEnd).rounded()),
            suggestedStarts: [previousEnd, projectedEffectiveEnd]
        )
    }
}
