import Foundation

private struct ClassifiedRateLimit {
    let window: RateLimitWindow
    let durationSeconds: Int
}

public struct CodexUsageStatus: Sendable, Hashable {
    public static let fiveHourDurationSeconds = 5 * 60 * 60
    public static let defaultSecondaryDurationSeconds = 7 * 24 * 60 * 60
    public static let weeklyClassThresholdSeconds = 24 * 60 * 60
    /// How close to `eventTimestamp + duration` a reported reset must be to count
    /// as the synthetic "fresh slot" rather than a real anchored window.
    public static let syntheticSlotToleranceSeconds: TimeInterval = 60
    public static let maxEventAgeSeconds: TimeInterval = 5 * 60 * 60

    public var eventTimestamp: Date
    public var primary: RateLimitWindow?
    public var secondary: RateLimitWindow?
    public var primaryWindowMinutes: Int?
    public var secondaryWindowMinutes: Int?
    public var planType: String?

    public init(
        eventTimestamp: Date,
        primary: RateLimitWindow? = nil,
        secondary: RateLimitWindow? = nil,
        primaryWindowMinutes: Int? = nil,
        secondaryWindowMinutes: Int? = nil,
        planType: String? = nil
    ) {
        self.eventTimestamp = eventTimestamp
        self.primary = primary
        self.secondary = secondary
        self.primaryWindowMinutes = primaryWindowMinutes
        self.secondaryWindowMinutes = secondaryWindowMinutes
        self.planType = planType
    }

    /// Duration in seconds for the primary window. Prefers the CLI-provided
    /// `window_minutes`/`windowDurationMins` field; falls back to the historical
    /// 5h constant when the CLI doesn't report a duration.
    public var primaryDurationSeconds: Int? {
        guard primary != nil else { return nil }
        guard let minutes = primaryWindowMinutes, minutes > 0 else {
            return Self.fiveHourDurationSeconds
        }
        return minutes * 60
    }

    /// Duration in seconds for the secondary window. Prefers the CLI-provided
    /// `window_minutes`/`windowDurationMins` field.
    public var secondaryDurationSeconds: Int {
        guard let minutes = secondaryWindowMinutes, minutes > 0 else {
            return Self.defaultSecondaryDurationSeconds
        }
        return minutes * 60
    }

    public var fiveHourStartAt: Date? {
        guard let limit = fiveHourClassLimit else { return nil }
        return limit.window.resetsAt.addingTimeInterval(-TimeInterval(limit.durationSeconds))
    }

    /// True when Codex appears to be reporting a real, anchored 5h window;
    /// false when no primary limit was reported or the reported `resetsAt` is
    /// the synthetic "fresh slot" value (`eventTimestamp + primaryDuration`)
    /// that Codex returns before any usage has anchored the current window.
    public var hasActivePrimaryWindow: Bool {
        guard let primary, let duration = primaryDurationSeconds else { return false }
        return Self.isActive(window: primary, durationSeconds: duration, eventTimestamp: eventTimestamp)
    }

    /// True when the duration-classified 5h slot is anchored. This follows the
    /// selected short window even if Codex reports it in the secondary slot.
    public var hasActiveFiveHourWindow: Bool {
        guard let limit = fiveHourClassLimit else { return false }
        return Self.isActive(
            window: limit.window,
            durationSeconds: limit.durationSeconds,
            eventTimestamp: eventTimestamp
        )
    }

    /// True when the reported weekly limit is Codex's synthetic "fresh slot"
    /// (`resets_at == eventTimestamp + window duration`) with no consumption:
    /// the weekly window you would get by starting now, not one that opened.
    /// Codex re-issues it on every poll with a new reset end, so persisting it
    /// writes one row per poll.
    ///
    /// Deliberately a two-sided band rather than the one-sided `isActive` used
    /// for the 5h class: a real anchored weekly window can report a reset a
    /// little farther out than one duration, and only the exact synthetic value
    /// should be rejected.
    public var isSyntheticFreshWeeklySlot: Bool {
        guard let limit = weeklyClassLimit, limit.window.usedPercentage <= 0 else { return false }
        let remaining = limit.window.resetsAt.timeIntervalSince(eventTimestamp)
        return abs(remaining - TimeInterval(limit.durationSeconds))
            <= Self.syntheticSlotToleranceSeconds
    }

    var fiveHourUsedPercentage: Double? {
        fiveHourClassLimit?.window.usedPercentage
    }

    var fiveHourResetsAt: Date? {
        fiveHourClassLimit?.window.resetsAt
    }

    var weeklyUsedPercentage: Double? {
        weeklyClassLimit?.window.usedPercentage
    }

    var weeklyResetsAt: Date? {
        weeklyClassLimit?.window.resetsAt
    }

    private static func isActive(
        window: RateLimitWindow,
        durationSeconds: Int,
        eventTimestamp: Date
    ) -> Bool {
        // Synthetic "fresh slot" reports `resetsAt ≈ eventTimestamp + duration`,
        // so remaining time ≈ full duration. A real anchored window has a
        // smaller remaining time. Use a small tolerance (5s) to avoid the
        // ~60s false-negative window right after anchoring.
        let remaining = window.resetsAt.timeIntervalSince(eventTimestamp)
        return remaining < TimeInterval(durationSeconds) - 5
    }

    public func normalizedUsage(
        providerID: ProviderID = .codex,
        capturedAt: Date = .now
    ) -> NormalizedUsage {
        let limit = fiveHourClassLimit ?? weeklyClassLimit
        return NormalizedUsage(
            providerID: providerID,
            capturedAt: capturedAt,
            windowStartedAt: limit.map {
                $0.window.resetsAt.addingTimeInterval(-TimeInterval($0.durationSeconds))
            },
            windowEndsAt: limit?.window.resetsAt,
            usedPercentage: limit?.window.usedPercentage,
            rawNotes: "Codex session token_count rate_limits"
        )
    }

    public func actualWindow(
        providerID: ProviderID = .codex,
        createdAt: Date = .now
    ) -> ActualWindow5h? {
        guard let limit = fiveHourClassLimit else { return nil }
        let startAt = limit.window.resetsAt.addingTimeInterval(-TimeInterval(limit.durationSeconds))
        return ActualWindow5h(
            providerID: providerID,
            startAt: startAt,
            durationSeconds: limit.durationSeconds,
            source: .detectedFromUsage,
            confidence: .estimated,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    public func secondaryActualWindow(
        providerID: ProviderID = .codex,
        usageSnapshotID: UUID? = nil,
        createdAt: Date = .now
    ) -> ActualWindow7d? {
        guard let limit = weeklyClassLimit else { return nil }
        let start = limit.window.resetsAt.addingTimeInterval(-TimeInterval(limit.durationSeconds))
        return ActualWindow7d(
            providerID: providerID,
            startAt: start,
            durationSeconds: limit.durationSeconds,
            usedPercentage: limit.window.usedPercentage,
            source: .detectedFromUsage,
            confidence: .estimated,
            usageSnapshotID: usageSnapshotID,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    /// True when Codex reported a 5h-class limit in either slot, classified by
    /// the reported window duration rather than by slot position.
    public var hasFiveHourClassLimit: Bool { fiveHourClassLimit != nil }

    /// True when Codex reported a weekly-class limit in either slot, classified
    /// by the reported window duration rather than by slot position.
    public var hasWeeklyClassLimit: Bool { weeklyClassLimit != nil }

    private var fiveHourClassLimit: ClassifiedRateLimit? {
        if let primary,
           let duration = primaryDurationSeconds,
           duration < Self.weeklyClassThresholdSeconds {
            return ClassifiedRateLimit(window: primary, durationSeconds: duration)
        }
        if let secondary, secondaryDurationSeconds < Self.weeklyClassThresholdSeconds {
            return ClassifiedRateLimit(window: secondary, durationSeconds: secondaryDurationSeconds)
        }
        return nil
    }

    private var weeklyClassLimit: ClassifiedRateLimit? {
        if let secondary, secondaryDurationSeconds >= Self.weeklyClassThresholdSeconds {
            return ClassifiedRateLimit(window: secondary, durationSeconds: secondaryDurationSeconds)
        }
        if let primary,
           let duration = primaryDurationSeconds,
           duration >= Self.weeklyClassThresholdSeconds {
            return ClassifiedRateLimit(window: primary, durationSeconds: duration)
        }
        return nil
    }

    public func isStale(now: Date = .now) -> Bool {
        now.timeIntervalSince(eventTimestamp) > Self.maxEventAgeSeconds
    }

    public func encodedPayload() -> String {
        var rateLimits: [String: Any] = [:]
        if let primary {
            var primaryPayload: [String: Any] = [
                "used_percent": primary.usedPercentage,
                "resets_at": Int(primary.resetsAt.timeIntervalSince1970)
            ]
            if let primaryWindowMinutes {
                primaryPayload["window_minutes"] = primaryWindowMinutes
            }
            rateLimits["primary"] = primaryPayload
        }
        if let secondary {
            var secondaryPayload: [String: Any] = [
                "used_percent": secondary.usedPercentage,
                "resets_at": Int(secondary.resetsAt.timeIntervalSince1970)
            ]
            if let secondaryWindowMinutes {
                secondaryPayload["window_minutes"] = secondaryWindowMinutes
            }
            rateLimits["secondary"] = secondaryPayload
        }
        if let planType {
            rateLimits["plan_type"] = planType
        }

        let object: [String: Any] = [
            "timestamp": DateTimeService.formatUTC(eventTimestamp),
            "rate_limits": rateLimits
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func parsePayload(_ rawJSON: String) throws -> CodexUsageStatus {
        let envelope = try decodeEnvelope(rawJSON)
        guard let rateLimits = envelope.resolvedRateLimits else {
            throw CodexUsageStatusParseError.missingRateLimits
        }
        return try makeStatus(timestamp: envelope.timestamp, rateLimits: rateLimits)
    }

    public static func parseJSONLLine(_ line: String) throws -> CodexUsageStatus {
        let envelope = try decodeEnvelope(line)
        guard envelope.type == "event_msg",
              envelope.payload?.type == "token_count",
              let rateLimits = envelope.payload?.rateLimits else {
            throw CodexUsageStatusParseError.notTokenCountEvent
        }
        return try makeStatus(timestamp: envelope.timestamp, rateLimits: rateLimits)
    }

    /// Parses any supported Codex usage payload shape: tries the current
    /// `codex app-server` response first, then falls back to the older flattened
    /// `{timestamp, rate_limits}` shape historically read from session JSONL.
    public static func parseAny(
        _ rawJSON: String,
        capturedAt: Date = .now
    ) throws -> CodexUsageStatus {
        if let appServer = try? parseAppServerResponse(rawJSON, capturedAt: capturedAt) {
            return appServer
        }
        return try parsePayload(rawJSON)
    }

    /// Parses the `result` payload from `codex app-server`'s
    /// `account/rateLimits/read` JSON-RPC response (camelCase shape with
    /// CLI-provided `windowDurationMins`).
    public static func parseAppServerResponse(
        _ rawJSON: String,
        capturedAt: Date = .now
    ) throws -> CodexUsageStatus {
        guard let data = rawJSON.data(using: .utf8) else {
            throw CodexUsageStatusParseError.invalidUTF8
        }
        let response = try JSONDecoder().decode(AppServerRateLimitsResponse.self, from: data)
        return try makeStatus(
            timestamp: capturedAt,
            rateLimits: response.rateLimits.toCodexRateLimitsPayload()
        )
    }

    private static func decodeEnvelope(_ rawJSON: String) throws -> CodexUsageEnvelope {
        guard let data = rawJSON.data(using: .utf8) else {
            throw CodexUsageStatusParseError.invalidUTF8
        }
        return try JSONDecoder().decode(CodexUsageEnvelope.self, from: data)
    }

    private static func makeStatus(
        timestamp: Date,
        rateLimits: CodexRateLimitsPayload
    ) throws -> CodexUsageStatus {
        guard rateLimits.primary != nil || rateLimits.secondary != nil else {
            throw CodexUsageStatusParseError.missingRateLimit
        }
        return CodexUsageStatus(
            eventTimestamp: timestamp,
            primary: try rateLimits.primary?.toRateLimitWindow(eventTimestamp: timestamp),
            secondary: try rateLimits.secondary?.toRateLimitWindow(eventTimestamp: timestamp),
            primaryWindowMinutes: rateLimits.primary?.windowMinutes,
            secondaryWindowMinutes: rateLimits.secondary?.windowMinutes,
            planType: rateLimits.planType
        )
    }
}

public enum CodexUsageStatusParseError: LocalizedError, Sendable {
    case invalidUTF8
    case invalidTimestamp(String)
    case missingRateLimits
    case missingRateLimit
    case missingPrimaryLimit
    case missingResetTime
    case notTokenCountEvent
    case noStatusEvents

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            "Codex usage payload was not valid UTF-8"
        case .invalidTimestamp(let value):
            "Codex usage payload contained an invalid timestamp: \(value)"
        case .missingRateLimits:
            "Codex usage payload did not include rate_limits"
        case .missingRateLimit:
            "Codex usage payload did not include a primary or secondary rate limit"
        case .missingPrimaryLimit:
            "Codex usage payload did not include rate_limits.primary"
        case .missingResetTime:
            "Codex usage payload did not include resets_at or resets_in_seconds"
        case .notTokenCountEvent:
            "Codex session line was not a token_count event"
        case .noStatusEvents:
            "Codex sessions did not contain a parseable token_count rate-limit event"
        }
    }
}

private struct CodexUsageEnvelope: Decodable {
    var timestamp: Date
    var type: String?
    var payload: CodexTokenCountPayload?
    var rateLimits: CodexRateLimitsPayload?

    var resolvedRateLimits: CodexRateLimitsPayload? {
        rateLimits ?? payload?.rateLimits
    }

    enum CodingKeys: String, CodingKey {
        case timestamp
        case type
        case payload
        case rateLimits = "rate_limits"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawTimestamp = try container.decode(String.self, forKey: .timestamp)
        guard let timestamp = Self.parseTimestamp(rawTimestamp) else {
            throw CodexUsageStatusParseError.invalidTimestamp(rawTimestamp)
        }
        self.timestamp = timestamp
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.payload = try container.decodeIfPresent(CodexTokenCountPayload.self, forKey: .payload)
        self.rateLimits = try container.decodeIfPresent(CodexRateLimitsPayload.self, forKey: .rateLimits)
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        if let date = DateTimeService.parseUTC(value) {
            return date
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: value)
    }
}

private struct CodexTokenCountPayload: Decodable {
    var type: String?
    var rateLimits: CodexRateLimitsPayload?

    enum CodingKeys: String, CodingKey {
        case type
        case rateLimits = "rate_limits"
    }
}

private struct CodexRateLimitsPayload: Decodable {
    var primary: CodexRateLimitPayload?
    var secondary: CodexRateLimitPayload?
    var planType: String?

    init(
        primary: CodexRateLimitPayload? = nil,
        secondary: CodexRateLimitPayload? = nil,
        planType: String? = nil
    ) {
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
    }

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case planType = "plan_type"
    }
}

private struct AppServerRateLimitsResponse: Decodable {
    var rateLimits: AppServerRateLimitsSnapshot
}

private struct AppServerRateLimitsSnapshot: Decodable {
    var primary: AppServerRateLimitWindow?
    var secondary: AppServerRateLimitWindow?
    var planType: String?

    func toCodexRateLimitsPayload() -> CodexRateLimitsPayload {
        CodexRateLimitsPayload(
            primary: primary.map {
                CodexRateLimitPayload(
                    usedPercentage: $0.usedPercent,
                    windowMinutes: $0.windowDurationMins,
                    resetsAt: $0.resetsAt,
                    resetsInSeconds: nil
                )
            },
            secondary: secondary.map {
                CodexRateLimitPayload(
                    usedPercentage: $0.usedPercent,
                    windowMinutes: $0.windowDurationMins,
                    resetsAt: $0.resetsAt,
                    resetsInSeconds: nil
                )
            },
            planType: planType
        )
    }
}

private struct AppServerRateLimitWindow: Decodable {
    var usedPercent: Double
    var resetsAt: Double?
    var windowDurationMins: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.usedPercent = try container.decodeCodexDouble(forKey: .usedPercent)
        self.resetsAt = try container.decodeCodexDoubleIfPresent(forKey: .resetsAt)
        self.windowDurationMins = try container.decodeCodexIntIfPresent(forKey: .windowDurationMins)
    }

    enum CodingKeys: String, CodingKey {
        case usedPercent
        case resetsAt
        case windowDurationMins
    }

    func toRateLimitWindow(capturedAt: Date) throws -> RateLimitWindow {
        guard let resetsAt else {
            throw CodexUsageStatusParseError.missingResetTime
        }
        let seconds = resetsAt > 10_000_000_000 ? resetsAt / 1_000 : resetsAt
        return RateLimitWindow(
            usedPercentage: usedPercent,
            resetsAt: Date(timeIntervalSince1970: seconds)
        )
    }
}

private struct CodexRateLimitPayload: Decodable {
    var usedPercentage: Double
    var windowMinutes: Int?
    var resetsAt: Double?
    var resetsInSeconds: Double?

    init(
        usedPercentage: Double,
        windowMinutes: Int? = nil,
        resetsAt: Double? = nil,
        resetsInSeconds: Double? = nil
    ) {
        self.usedPercentage = usedPercentage
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.resetsInSeconds = resetsInSeconds
    }

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
        case resetsInSeconds = "resets_in_seconds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.usedPercentage = try container.decodeCodexDouble(forKey: .usedPercentage)
        self.windowMinutes = try container.decodeCodexIntIfPresent(forKey: .windowMinutes)
        self.resetsAt = try container.decodeCodexDoubleIfPresent(forKey: .resetsAt)
        self.resetsInSeconds = try container.decodeCodexDoubleIfPresent(forKey: .resetsInSeconds)
    }

    func toRateLimitWindow(eventTimestamp: Date) throws -> RateLimitWindow {
        if let resetsAt {
            let seconds = resetsAt > 10_000_000_000 ? resetsAt / 1_000 : resetsAt
            return RateLimitWindow(
                usedPercentage: usedPercentage,
                resetsAt: Date(timeIntervalSince1970: seconds)
            )
        }
        if let resetsInSeconds {
            return RateLimitWindow(
                usedPercentage: usedPercentage,
                resetsAt: eventTimestamp.addingTimeInterval(resetsInSeconds)
            )
        }
        throw CodexUsageStatusParseError.missingResetTime
    }
}

private extension KeyedDecodingContainer {
    func decodeCodexDouble(forKey key: Key) throws -> Double {
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decode(String.self, forKey: key),
           let double = Double(value) {
            return double
        }
        throw DecodingError.typeMismatch(
            Double.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected Double, Int, or numeric String"
            )
        )
    }

    func decodeCodexDoubleIfPresent(forKey key: Key) throws -> Double? {
        if !contains(key) {
            return nil
        }
        return try decodeCodexDouble(forKey: key)
    }

    func decodeCodexIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decode(String.self, forKey: key),
           let int = Int(value) {
            return int
        }
        return nil
    }
}
