import Foundation

public struct CodexUsageStatus: Sendable, Hashable {
    public static let fiveHourDurationSeconds = 5 * 60 * 60

    public var eventTimestamp: Date
    public var primary: RateLimitWindow
    public var secondary: RateLimitWindow?
    public var primaryWindowMinutes: Int?
    public var secondaryWindowMinutes: Int?
    public var planType: String?

    public init(
        eventTimestamp: Date,
        primary: RateLimitWindow,
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

    public var fiveHourStartAt: Date {
        primary.resetsAt.addingTimeInterval(-TimeInterval(Self.fiveHourDurationSeconds))
    }

    public func normalizedUsage(
        providerID: ProviderID = .codex,
        capturedAt: Date = .now
    ) -> NormalizedUsage {
        NormalizedUsage(
            providerID: providerID,
            capturedAt: capturedAt,
            windowStartedAt: fiveHourStartAt,
            windowEndsAt: primary.resetsAt,
            usedPercentage: primary.usedPercentage,
            rawNotes: "Codex session token_count rate_limits"
        )
    }

    public func actualWindow(
        providerID: ProviderID = .codex,
        createdAt: Date = .now
    ) -> ActualWindow {
        ActualWindow(
            providerID: providerID,
            startAt: fiveHourStartAt,
            durationSeconds: Self.fiveHourDurationSeconds,
            source: .detectedFromUsage,
            confidence: .estimated,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    public func encodedPayload() -> String {
        var primaryPayload: [String: Any] = [
            "used_percent": primary.usedPercentage,
            "resets_at": Int(primary.resetsAt.timeIntervalSince1970)
        ]
        if let primaryWindowMinutes {
            primaryPayload["window_minutes"] = primaryWindowMinutes
        }

        var rateLimits: [String: Any] = ["primary": primaryPayload]
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
        guard let primaryPayload = rateLimits.primary else {
            throw CodexUsageStatusParseError.missingPrimaryLimit
        }
        return CodexUsageStatus(
            eventTimestamp: timestamp,
            primary: try primaryPayload.toRateLimitWindow(eventTimestamp: timestamp),
            secondary: try rateLimits.secondary?.toRateLimitWindow(eventTimestamp: timestamp),
            primaryWindowMinutes: primaryPayload.windowMinutes,
            secondaryWindowMinutes: rateLimits.secondary?.windowMinutes,
            planType: rateLimits.planType
        )
    }
}

public enum CodexUsageStatusParseError: LocalizedError, Sendable {
    case invalidUTF8
    case invalidTimestamp(String)
    case missingRateLimits
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

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case planType = "plan_type"
    }
}

private struct CodexRateLimitPayload: Decodable {
    var usedPercentage: Double
    var windowMinutes: Int?
    var resetsAt: Double?
    var resetsInSeconds: Double?

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
