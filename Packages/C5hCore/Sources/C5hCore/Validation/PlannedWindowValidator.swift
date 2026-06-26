import Foundation

public struct PlannedWindowValidationResult: Sendable, Hashable {
    public var conflictingWindowIDs: [UUID]
    public var hasConflict: Bool { !conflictingWindowIDs.isEmpty }
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
            conflictingWindowIDs: plannedResult.conflictingWindowIDs + actualConflicts.map { $0.id }
        )
    }
}
