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
        plannedWindowRepository: any PlannedWindowRepository
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
                let windows = try await actual5hRepository.fetchWindows(
                    for: DateInterval(start: now, duration: 1)
                )
                return windows.contains {
                    $0.providerID == providerID && $0.startAt <= now && $0.endAt >= now
                }
            },
            hasPendingPlannedWindow: { providerID, now in
                let windows = try await plannedWindowRepository.fetchAll()
                return windows.contains {
                    $0.providerID == providerID
                        && !$0.status.isTerminal
                        && $0.startAt <= now
                        && now < $0.endAt
                }
            }
        )
    }
}
