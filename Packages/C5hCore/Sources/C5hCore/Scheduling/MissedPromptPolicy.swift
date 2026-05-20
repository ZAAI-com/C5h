import Foundation

public struct MissedPromptPolicy: Sendable, Hashable {
    public var graceSeconds: TimeInterval

    public init(graceSeconds: TimeInterval = 15 * 60) {
        // Invariant: non-negative — a negative grace would invert isOverdue.
        self.graceSeconds = max(0, graceSeconds)
    }

    public static let `default` = MissedPromptPolicy()

    public func isOverdue(runAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(runAt) > graceSeconds
    }
}
