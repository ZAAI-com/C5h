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
        let candidateInterval = DateInterval(
            start: candidate.startAt,
            duration: TimeInterval(candidate.durationSeconds)
        )
        let conflicts = existing.filter { other in
            guard other.id != candidate.id else { return false }
            guard other.providerID == candidate.providerID else { return false }
            guard other.durationSeconds >= 0 else { return false }
            let otherInterval = DateInterval(
                start: other.startAt,
                duration: TimeInterval(other.durationSeconds)
            )
            return otherInterval.intersects(candidateInterval)
        }
        return PlannedWindowValidationResult(
            conflictingWindowIDs: conflicts.map { $0.id }
        )
    }
}
