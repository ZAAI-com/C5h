import Foundation

public struct HelperHeartbeatEvidence: Sendable, Hashable {
    public var lastSeenAt: Date
    public var pid: Int?
    public var version: String?

    public init(lastSeenAt: Date, pid: Int?, version: String? = nil) {
        self.lastSeenAt = lastSeenAt
        self.pid = pid
        self.version = version
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
    /// True when the running helper reports a build identity that differs from
    /// the binary the app would launch (i.e. the process is running stale code).
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

    /// `expectedVersion` is the build identity of the helper binary the app
    /// would launch (see `HelperBuildStamp`). When provided and the heartbeat
    /// reports a different version, the evaluation is flagged `outdated`. Pass
    /// `nil` to skip the check (e.g. when the expected binary is unknown).
    public func evaluate(
        heartbeat: HelperHeartbeatEvidence?,
        now: Date,
        expectedVersion: String? = nil,
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

        let outdated: Bool
        if let expectedVersion, let reported = heartbeat.version {
            outdated = reported != expectedVersion
        } else {
            outdated = false
        }

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
