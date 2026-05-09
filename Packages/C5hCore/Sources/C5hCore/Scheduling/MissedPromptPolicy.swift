import Foundation

public struct MissedPromptPolicy: Sendable, Hashable {
    public var graceSeconds: TimeInterval

    public init(graceSeconds: TimeInterval = 15 * 60) {
        self.graceSeconds = graceSeconds
    }

    public static let `default` = MissedPromptPolicy()

    public func isOverdue(runAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(runAt) > graceSeconds
    }
}
