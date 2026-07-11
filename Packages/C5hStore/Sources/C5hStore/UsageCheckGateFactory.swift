import Foundation
import C5hCore

public extension UsageCheckGate {
    /// Builds a gate wired to the GRDB repositories. C5hCore defines the gate in
    /// terms of closures (it can't depend on C5hStore), so this connects those
    /// closures to the repository protocols. Shared by the app (dashboard,
    /// calendar) and the background helper so the per-provider "check when idle"
    /// rule is evaluated identically everywhere.
    static func make(
        appSettings: any AppSettingsRepository,
        actual5hRepository: any ActualWindow5hRepository,
        plannedWindowRepository: any PlannedWindowRepository,
        usageSnapshotRepository: any UsageSnapshotRepository,
        localActivityDetector: ClaudeLocalActivityDetector
    ) -> UsageCheckGate {
        UsageCheckGate(
            isIdleCheckEnabled: { providerID in
                let stored = (try? await appSettings.get(
                    AppSettingsKeys.checkUsageWhenIdle(for: providerID),
                    as: Bool.self
                )) ?? nil
                return stored ?? AppSettingsKeys.defaultCheckUsageWhenIdle
            },
            hasActiveWindow: { providerID, now in
                // Quota-consuming probes must not launch in the final stretch of
                // a window: one launched seconds before expiry lands its startup
                // request after it and opens a fresh window.
                let margin = providerID.usageProbeConsumesQuota
                    ? UsageCheckGate.consumingProbeEndMargin
                    : 0
                let windows = try await actual5hRepository.fetchWindows(
                    for: DateInterval(start: now, duration: 1)
                )
                let hasRecordedWindow = windows.contains {
                    $0.providerID == providerID
                        && $0.startAt <= now
                        && $0.endAt >= now.addingTimeInterval(margin)
                }
                if hasRecordedWindow {
                    return true
                }
                // Believed-active fallback for consuming providers: a window
                // whose usage rounds to 0% never produces a recorded row
                // (UsageFetcher drops idle-looking reports), but the latest
                // snapshot's reported window end still marks it as open, and
                // probing inside an open window is free.
                guard providerID.usageProbeConsumesQuota,
                      let snapshot = try await usageSnapshotRepository.fetchLatest(
                        providerID: providerID
                      ),
                      let windowEndsAt = UsageNormalizer.decode(snapshot.normalizedJSON)?.windowEndsAt
                else {
                    return false
                }
                return windowEndsAt >= now.addingTimeInterval(margin)
            },
            hasPendingPlannedWindow: { providerID, now in
                let windows = try await plannedWindowRepository.fetchWindows(
                    for: DateInterval(start: now, duration: 1)
                )
                return windows.contains {
                    $0.providerID == providerID
                        && !$0.status.isTerminal
                        && $0.startAt <= now
                        && now < $0.endAt
                }
            },
            hasRecentLocalActivity: { providerID, now in
                // The detector reads Claude Code's session transcripts; other
                // providers have no local evidence source and fail closed.
                guard providerID == .claude else { return false }
                let storedInterval = (try? await appSettings.get(
                    AppSettingsKeys.usageRefreshIntervalSeconds(for: providerID),
                    as: Int.self
                )) ?? nil
                let refreshInterval = TimeInterval(
                    storedInterval ?? AppSettingsKeys.defaultUsageRefreshIntervalSeconds
                )
                // Activity stays valid proof of an open window for at least two
                // poll intervals (so activity between checks isn't missed) and
                // at least 15 minutes; beyond that, stale transcripts must not
                // reopen probing hours later.
                let lookback = max(2 * refreshInterval, 900)
                let floor = now.addingTimeInterval(-lookback)
                // Activity recorded inside an already-tracked window must not
                // count once that window ends, so the reference starts at the
                // latest recorded window end within the lookback.
                let overlapping = (try? await actual5hRepository.fetchWindows(
                    for: DateInterval(start: floor, end: now)
                )) ?? []
                let lastRecordedEnd = overlapping
                    .filter { $0.providerID == providerID }
                    .map(\.endAt)
                    .max()
                let reference = max(lastRecordedEnd ?? .distantPast, floor)
                return await localActivityDetector.hasActivity(since: reference)
            }
        )
    }
}
