import Foundation

public struct HelperHeartbeatEvidence: Sendable, Hashable {
    public var lastSeenAt: Date
    public var pid: Int?

    public init(lastSeenAt: Date, pid: Int?) {
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

    public init(
        status: HelperHealthStatus,
        lastSeenAt: Date?,
        ageSeconds: TimeInterval?,
        pid: Int?
    ) {
        self.status = status
        self.lastSeenAt = lastSeenAt
        self.ageSeconds = ageSeconds
        self.pid = pid
    }
}

public struct HelperHealthEvaluator: Sendable {
    public static let defaultStaleAfterSeconds: TimeInterval = 90

    public var staleAfterSeconds: TimeInterval

    public init(staleAfterSeconds: TimeInterval = Self.defaultStaleAfterSeconds) {
        self.staleAfterSeconds = staleAfterSeconds
    }

    public func evaluate(
        heartbeat: HelperHeartbeatEvidence?,
        now: Date,
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

        let ageSeconds = max(0, now.timeIntervalSince(heartbeat.lastSeenAt))
        if ageSeconds > staleAfterSeconds {
            return HelperHealthEvaluation(
                status: .stale,
                lastSeenAt: heartbeat.lastSeenAt,
                ageSeconds: ageSeconds,
                pid: heartbeat.pid
            )
        }

        guard let pid = heartbeat.pid else {
            return HelperHealthEvaluation(
                status: .unknown,
                lastSeenAt: heartbeat.lastSeenAt,
                ageSeconds: ageSeconds,
                pid: nil
            )
        }

        return HelperHealthEvaluation(
            status: isProcessAlive(pid) ? .running : .stopped,
            lastSeenAt: heartbeat.lastSeenAt,
            ageSeconds: ageSeconds,
            pid: pid
        )
    }
}
