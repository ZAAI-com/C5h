import Foundation

public struct NormalizedUsage: Codable, Sendable, Hashable {
    public var providerID: ProviderID
    public var capturedAt: Date
    public var messageCount: Int?
    public var windowStartedAt: Date?
    public var windowEndsAt: Date?
    public var usedPercentage: Double?
    public var rawNotes: String?

    public init(
        providerID: ProviderID,
        capturedAt: Date = .now,
        messageCount: Int? = nil,
        windowStartedAt: Date? = nil,
        windowEndsAt: Date? = nil,
        usedPercentage: Double? = nil,
        rawNotes: String? = nil
    ) {
        self.providerID = providerID
        self.capturedAt = capturedAt
        self.messageCount = messageCount
        self.windowStartedAt = windowStartedAt
        self.windowEndsAt = windowEndsAt
        self.usedPercentage = usedPercentage
        self.rawNotes = rawNotes
    }
}

public enum UsageNormalizer {
    /// Best-effort tolerant parser: pulls common fields out of provider usage
    /// JSON without making assumptions about exact schemas (those drift often).
    public static func normalize(
        rawJSON: String,
        providerID: ProviderID,
        capturedAt: Date = .now
    ) -> NormalizedUsage {
        if providerID == .claude,
           let status = try? ClaudeUsageStatus.parsePayload(rawJSON) {
            return status.normalizedUsage(providerID: providerID, capturedAt: capturedAt)
        }
        if providerID == .codex,
           let status = try? CodexUsageStatus.parsePayload(rawJSON) {
            return status.normalizedUsage(providerID: providerID, capturedAt: capturedAt)
        }

        guard
            let data = rawJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any]
        else {
            return NormalizedUsage(
                providerID: providerID,
                capturedAt: capturedAt,
                rawNotes: rawJSON.isEmpty ? nil : "non-JSON usage payload"
            )
        }

        var normalized = NormalizedUsage(providerID: providerID, capturedAt: capturedAt)
        if let count = dict["messages"] as? Int { normalized.messageCount = count }
        if let count = dict["message_count"] as? Int { normalized.messageCount = count }
        if let count = dict["count"] as? Int, normalized.messageCount == nil {
            normalized.messageCount = count
        }
        if let start = (dict["window_started_at"] as? String).flatMap(DateTimeService.parseUTC) {
            normalized.windowStartedAt = start
        }
        if let end = (dict["window_ends_at"] as? String).flatMap(DateTimeService.parseUTC) {
            normalized.windowEndsAt = end
        }
        return normalized
    }

    public static func encode(_ value: NormalizedUsage) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(value)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Inverse of `encode`. Returns nil for payloads that do not decode as
    /// `NormalizedUsage` (older or hand-edited rows).
    public static func decode(_ normalizedJSON: String) -> NormalizedUsage? {
        guard let data = normalizedJSON.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(NormalizedUsage.self, from: data)
    }
}
