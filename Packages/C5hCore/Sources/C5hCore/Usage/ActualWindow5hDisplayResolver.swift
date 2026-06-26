import Foundation

public struct ActualWindow5hDisplaySegment: Identifiable, Sendable, Hashable {
    public var id: UUID { window.id }
    public let window: ActualWindow5h
    public let startAt: Date
    public let endAt: Date

    public init(window: ActualWindow5h, startAt: Date? = nil, endAt: Date? = nil) {
        self.window = window
        self.startAt = startAt ?? window.startAt
        self.endAt = endAt ?? window.endAt
    }

    public var durationSeconds: Int {
        max(0, Int(endAt.timeIntervalSince(startAt).rounded()))
    }
}

public enum ActualWindow5hDisplayResolver {
    public static let resetEndTolerance: TimeInterval = 60

    /// Builds display-only actual-window segments. Persisted windows remain full
    /// provider-reported rows, but when a detected 5h reset starts a new window
    /// before an earlier same-provider window ended, the earlier display segment
    /// stops at the reset window's start.
    public static func segments(
        for windows: [ActualWindow5h],
        resetEvents: [UsageResetEvent],
        resetEndTolerance: TimeInterval = Self.resetEndTolerance
    ) -> [ActualWindow5hDisplaySegment] {
        guard !windows.isEmpty else { return [] }
        let fiveHourResets = resetEvents.filter { $0.kind == .fiveHour }
        guard !fiveHourResets.isEmpty else {
            return windows.compactMap { segment(for: $0, endAt: $0.endAt) }
        }

        var displayEndByWindowID = Dictionary(
            uniqueKeysWithValues: windows.map { ($0.id, $0.endAt) }
        )

        for event in fiveHourResets {
            guard let resetWindow = resetWindow(
                for: event,
                in: windows,
                tolerance: resetEndTolerance
            ) else { continue }
            let boundary = resetWindow.startAt

            for window in windows where window.providerID == event.providerID && window.id != resetWindow.id {
                let currentEnd = displayEndByWindowID[window.id] ?? window.endAt
                guard window.startAt < boundary, boundary < currentEnd else { continue }
                displayEndByWindowID[window.id] = boundary
            }
        }

        return windows.compactMap { window in
            segment(for: window, endAt: displayEndByWindowID[window.id] ?? window.endAt)
        }
    }

    private static func resetWindow(
        for event: UsageResetEvent,
        in windows: [ActualWindow5h],
        tolerance: TimeInterval
    ) -> ActualWindow5h? {
        windows
            .filter {
                $0.providerID == event.providerID
                    && abs($0.endAt.timeIntervalSince(event.newResetEnd)) <= tolerance
            }
            .sorted {
                let lhsDelta = abs($0.endAt.timeIntervalSince(event.newResetEnd))
                let rhsDelta = abs($1.endAt.timeIntervalSince(event.newResetEnd))
                if lhsDelta != rhsDelta { return lhsDelta < rhsDelta }
                return $0.startAt < $1.startAt
            }
            .first
    }

    private static func segment(
        for window: ActualWindow5h,
        endAt: Date
    ) -> ActualWindow5hDisplaySegment? {
        guard endAt > window.startAt else { return nil }
        return ActualWindow5hDisplaySegment(window: window, endAt: endAt)
    }
}
