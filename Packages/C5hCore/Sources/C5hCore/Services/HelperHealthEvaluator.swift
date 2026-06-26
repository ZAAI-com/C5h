import Foundation

public struct HelperHeartbeatEvidence: Sendable, Hashable {
    public var startedAt: Date
    public var lastSeenAt: Date
    public var pid: Int?

    public init(startedAt: Date, lastSeenAt: Date, pid: Int?) {
        self.startedAt = startedAt
        self.lastSeenAt = lastSeenAt
        self.pid = pid
    }
}

public enum HelperHealthStatus: Sendable, Hashable {
    case neverSeen
    case running
    case stale
    case stopped
    case unknown
}

public struct HelperHealthEvaluation: Sendable, Hashable {
    public var status: HelperHealthStatus
    public var lastSeenAt: Date?
    public var ageSeconds: TimeInterval?
    public var pid: Int?
    /// True when the running helper started before the helper binary currently
    /// on disk was built.
    public var outdated: Bool

    public init(
        status: HelperHealthStatus,
        lastSeenAt: Date?,
        ageSeconds: TimeInterval?,
        pid: Int?,
        outdated: Bool = false
    ) {
        self.status = status
        self.lastSeenAt = lastSeenAt
        self.ageSeconds = ageSeconds
        self.pid = pid
        self.outdated = outdated
    }
}

public struct HelperHealthEvaluator: Sendable {
    public static let defaultStaleAfterSeconds: TimeInterval = 90

    public var staleAfterSeconds: TimeInterval

    public init(staleAfterSeconds: TimeInterval = Self.defaultStaleAfterSeconds) {
        self.staleAfterSeconds = staleAfterSeconds
    }

    /// `expectedBinaryModifiedAt` is the modification date of the helper binary
    /// the app would launch. When it is newer than the running helper's
    /// `startedAt`, the evaluation is flagged `outdated`.
    public func evaluate(
        heartbeat: HelperHeartbeatEvidence?,
        now: Date,
        expectedBinaryModifiedAt: Date? = nil,
        isProcessAlive: @Sendable (Int) -> Bool
    ) -> HelperHealthEvaluation {
        guard let heartbeat else {
            return HelperHealthEvaluation(
                status: .neverSeen,
                lastSeenAt: nil,
                ageSeconds: nil,
                pid: nil
            )
        }

        let outdated = expectedBinaryModifiedAt.map { $0 > heartbeat.startedAt } ?? false

        let ageSeconds = max(0, now.timeIntervalSince(heartbeat.lastSeenAt))
        if ageSeconds > staleAfterSeconds {
            return HelperHealthEvaluation(
                status: .stale,
                lastSeenAt: heartbeat.lastSeenAt,
                ageSeconds: ageSeconds,
                pid: heartbeat.pid,
                outdated: outdated
            )
        }

        guard let pid = heartbeat.pid else {
            return HelperHealthEvaluation(
                status: .unknown,
                lastSeenAt: heartbeat.lastSeenAt,
                ageSeconds: ageSeconds,
                pid: nil,
                outdated: outdated
            )
        }

        return HelperHealthEvaluation(
            status: isProcessAlive(pid) ? .running : .stopped,
            lastSeenAt: heartbeat.lastSeenAt,
            ageSeconds: ageSeconds,
            pid: pid,
            outdated: outdated
        )
    }
}
