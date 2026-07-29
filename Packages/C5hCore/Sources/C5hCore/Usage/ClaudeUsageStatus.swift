import Foundation

public struct ClaudeUsageStatus: Sendable, Hashable {
    public static let sentinel = "C5H_RATE_LIMITS:"
    public static let fiveHourDurationSeconds = 5 * 60 * 60
    public static let sevenDayDurationSeconds = 7 * 24 * 60 * 60

    public var fiveHour: RateLimitWindow
    public var sevenDay: RateLimitWindow?

    public init(fiveHour: RateLimitWindow, sevenDay: RateLimitWindow? = nil) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    public var fiveHourStartAt: Date {
        fiveHour.resetsAt.addingTimeInterval(-TimeInterval(Self.fiveHourDurationSeconds))
    }

    /// True when the reported 5h window reflects consumption above Claude's
    /// ~1% reporting resolution. Claude's boundary is a real anchored window,
    /// not a rolling placeholder: historically C5h's own REPL probes kept the
    /// account non-idle (each probe's startup makes an API request, and on an
    /// idle account that opens a fresh window at the previous expiry bucket),
    /// which made idle reports look like a rolling boundary. Probes are now
    /// gated so they only run once a window is already open (`UsageCheckGate`),
    /// and on the routine poll path this guard is combined with
    /// `isFreshFiveHourAnchor`: a 0%-usage report is kept when its start is a
    /// fresh anchor (a live window used below the reporting resolution) and
    /// dropped only when it is the provider's idle boundary chained onto the
    /// previous window's end, so a mis-gated probe still cannot fabricate one.
    /// The trigger-anchoring path bypasses the check on purpose via
    /// `requireActiveWindow: false` (a wake prompt just opened the window).
    public var hasActiveFiveHourWindow: Bool {
        fiveHour.usedPercentage > 0
    }

    /// Whether a 0%-usage 5h report is a *confirmed* genuine fresh anchor rather
    /// than the provider's idle boundary chained onto the previous window's end.
    /// Claude chains an idle window so its start lands on the prior window's end;
    /// a window whose start sits more than `tolerance` away from that boundary
    /// was opened by real activity (its sub-1% usage is simply below Claude's
    /// reporting resolution). A nil `previousWindowEnd` (no prior window on
    /// record within the lookup horizon) returns false: freshness cannot be
    /// confirmed, so the caller keeps the conservative drop-at-0% default until
    /// usage registers, and no mis-gated probe can fabricate a window.
    public func isFreshFiveHourAnchor(previousWindowEnd: Date?, tolerance: TimeInterval) -> Bool {
        guard let previousWindowEnd else { return false }
        return abs(fiveHourStartAt.timeIntervalSince(previousWindowEnd)) > tolerance
    }

    public var sevenDayStartAt: Date? {
        sevenDay?.resetsAt.addingTimeInterval(-TimeInterval(Self.sevenDayDurationSeconds))
    }

    public func normalizedUsage(
        providerID: ProviderID = .claude,
        capturedAt: Date = .now
    ) -> NormalizedUsage {
        NormalizedUsage(
            providerID: providerID,
            capturedAt: capturedAt,
            windowStartedAt: fiveHourStartAt,
            windowEndsAt: fiveHour.resetsAt,
            usedPercentage: fiveHour.usedPercentage,
            rawNotes: "Claude statusLine rate_limits"
        )
    }

    public func actualWindow(
        providerID: ProviderID = .claude,
        createdAt: Date = .now
    ) -> ActualWindow5h {
        ActualWindow5h(
            providerID: providerID,
            startAt: fiveHourStartAt,
            durationSeconds: Self.fiveHourDurationSeconds,
            source: .detectedFromUsage,
            confidence: .estimated,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    public func sevenDayActualWindow(
        providerID: ProviderID = .claude,
        usageSnapshotID: UUID? = nil,
        createdAt: Date = .now
    ) -> ActualWindow7d? {
        guard let sevenDay, let start = sevenDayStartAt else { return nil }
        return ActualWindow7d(
            providerID: providerID,
            startAt: start,
            durationSeconds: Self.sevenDayDurationSeconds,
            usedPercentage: sevenDay.usedPercentage,
            source: .detectedFromUsage,
            confidence: .estimated,
            usageSnapshotID: usageSnapshotID,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    public static func parsePayload(_ rawJSON: String) throws -> ClaudeUsageStatus {
        guard let data = rawJSON.data(using: .utf8) else {
            throw ClaudeUsageStatusParseError.invalidUTF8
        }
        let payload = try JSONDecoder().decode(StatusLinePayload.self, from: data)
        guard let fiveHour = payload.rateLimits?.fiveHour else {
            throw ClaudeUsageStatusParseError.missingFiveHourLimit
        }
        return ClaudeUsageStatus(
            fiveHour: fiveHour.toRateLimitWindow(),
            sevenDay: payload.rateLimits?.sevenDay?.toRateLimitWindow()
        )
    }

    public static func parseLatestSentinel(in output: String) throws -> ClaudeUsageStatus {
        for payload in sentinelPayloads(in: output).reversed() {
            if let status = try? parsePayload(payload) {
                return status
            }
        }
        throw ClaudeUsageStatusParseError.missingSentinel
    }

    public static func sentinelPayloads(in output: String) -> [String] {
        let cleaned = stripANSISequences(from: output)
        var payloads: [String] = []
        var searchStart = cleaned.startIndex

        while let range = cleaned.range(of: sentinel, range: searchStart..<cleaned.endIndex) {
            let suffix = cleaned[range.upperBound...]
            if let json = firstJSONObject(in: String(suffix)) {
                payloads.append(json)
            }
            searchStart = range.upperBound
        }

        return payloads
    }

    private static func stripANSISequences(from string: String) -> String {
        string.replacingOccurrences(
            of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
    }

    private static func firstJSONObject(in string: String) -> String? {
        var start: String.Index?
        var depth = 0
        var inString = false
        var isEscaped = false

        for index in string.indices {
            let character = string[index]

            if start == nil {
                guard character == "{" else { continue }
                start = index
                depth = 1
                continue
            }

            if inString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            switch character {
            case "\"":
                inString = true
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0, let start {
                    return String(string[start...index])
                }
            default:
                continue
            }
        }

        return nil
    }
}

public struct RateLimitWindow: Sendable, Hashable {
    public var usedPercentage: Double
    public var resetsAt: Date

    public init(usedPercentage: Double, resetsAt: Date) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }
}

public enum ClaudeUsageStatusParseError: LocalizedError, Sendable {
    case invalidUTF8
    case missingSentinel
    case missingFiveHourLimit
    case invalidTimestamp

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            "Claude usage payload was not valid UTF-8"
        case .missingSentinel:
            "Claude usage output did not contain a C5H rate-limit sentinel"
        case .missingFiveHourLimit:
            "Claude usage payload did not include rate_limits.five_hour"
        case .invalidTimestamp:
            "Claude usage payload contained an invalid reset timestamp"
        }
    }
}

private struct StatusLinePayload: Decodable {
    var rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }
}

private struct RateLimits: Decodable {
    var fiveHour: RateLimitPayload?
    var sevenDay: RateLimitPayload?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct RateLimitPayload: Decodable {
    var usedPercentage: Double
    var resetsAt: Date

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.usedPercentage = try container.decodeLossyDouble(forKey: .usedPercentage)
        self.resetsAt = try container.decodeUnixTimestamp(forKey: .resetsAt)
    }

    func toRateLimitWindow() -> RateLimitWindow {
        RateLimitWindow(usedPercentage: usedPercentage, resetsAt: resetsAt)
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyDouble(forKey key: Key) throws -> Double {
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

    func decodeUnixTimestamp(forKey key: Key) throws -> Date {
        if let value = try? decodeLossyDouble(forKey: key) {
            let seconds = value > 10_000_000_000 ? value / 1_000 : value
            return Date(timeIntervalSince1970: seconds)
        }
        if let value = try? decode(String.self, forKey: key),
           let date = DateTimeService.parseUTC(value) {
            return date
        }
        throw ClaudeUsageStatusParseError.invalidTimestamp
    }
}
