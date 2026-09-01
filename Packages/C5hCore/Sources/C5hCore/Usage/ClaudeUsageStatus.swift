import Foundation

public struct ClaudeUsageStatus: Sendable, Hashable {
    public static let sentinel = "C5H_RATE_LIMITS:"
    public static let fiveHourDurationSeconds = 5 * 60 * 60
    public static let fiveHourTimerToleranceSeconds = 60
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

    /// Whether Claude reported a plausible live 5h countdown at capture time.
    /// The timer is authoritative even when usage rounds down to 0%; percentage
    /// is display data, not an activity signal. A small tolerance accommodates
    /// clock skew and provider-side rounding around a newly opened window.
    public func hasLiveFiveHourTimer(
        capturedAt: Date,
        tolerance: TimeInterval = TimeInterval(Self.fiveHourTimerToleranceSeconds)
    ) -> Bool {
        let remaining = fiveHour.resetsAt.timeIntervalSince(capturedAt)
        return remaining > 0
            && remaining <= TimeInterval(Self.fiveHourDurationSeconds) + tolerance
    }

    /// Grid the provider advances an unopened 5h slot on. While the account is
    /// idle Claude reports `resets_at = (capture time floored to this grid) + 5h`
    /// at 0% used, and that boundary slides forward one step at a time, so every
    /// poll sees a different reset end for a window that never opened.
    public static let prospectiveSlotSlideSeconds = 10 * 60
    /// Clock skew allowed on top of the slide grid. `capturedAt` is stamped when
    /// the probe process finishes, several seconds after the payload was read, so
    /// a slot read just before a grid boundary is stamped just after it.
    public static let prospectiveSlotSkewSeconds = 60

    /// Whether the reported 5h limit is the provider's *prospective* slot (the
    /// window you would get by starting now) rather than a window that actually
    /// opened. Such a slot reports no consumption and starts within one slide
    /// step of the capture; persisting it writes a new row on every poll instead
    /// of tracking one real window.
    ///
    /// A report carrying any consumption, or one whose start has stopped moving
    /// (older than a slide step, which includes the boundary Claude chains onto
    /// a previous window's end), describes a real window and is not prospective.
    public func isProspectiveFiveHourSlot(capturedAt: Date) -> Bool {
        guard fiveHour.usedPercentage <= 0 else { return false }
        return capturedAt.timeIntervalSince(fiveHourStartAt)
            < TimeInterval(Self.prospectiveSlotSlideSeconds + Self.prospectiveSlotSkewSeconds)
    }

    /// Weekly counterpart: a synthetic slot reports `resets_at` almost exactly
    /// one full week out from the capture with no consumption. Claude's weekly
    /// boundary is stable, so this normally never fires; it keeps the two
    /// providers symmetric (see `CodexUsageStatus.isSyntheticFreshWeeklySlot`).
    public func isProspectiveSevenDaySlot(capturedAt: Date) -> Bool {
        guard let sevenDay, sevenDay.usedPercentage <= 0 else { return false }
        let remaining = sevenDay.resetsAt.timeIntervalSince(capturedAt)
        return abs(remaining - TimeInterval(Self.sevenDayDurationSeconds))
            <= TimeInterval(Self.prospectiveSlotSkewSeconds)
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
