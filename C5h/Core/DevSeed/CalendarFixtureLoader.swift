#if DEBUG
import Foundation
import C5hCore
import C5hStore

enum CalendarFixtureLoader {
    static func loadIfNeeded(
        plannedRepository: any PlannedWindowRepository,
        actualRepository: any ActualWindowRepository
    ) async {
        do {
            let existingPlanned = try await plannedRepository.fetchAll()
            guard existingPlanned.isEmpty else { return }
        } catch {
            return
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today

        func at(_ base: Date, hour: Int, minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }

        let plannedWindows: [PlannedWindow] = [
            PlannedWindow(
                providerID: .claude,
                startAt: at(today, hour: 9),
                durationSeconds: 5 * 3600,
                projectPath: "/Users/dev/projects/widget",
                status: .triggered
            ),
            PlannedWindow(
                providerID: .codex,
                startAt: at(today, hour: 15),
                durationSeconds: 5 * 3600,
                projectPath: "/Users/dev/projects/api",
                status: .scheduled
            ),
            PlannedWindow(
                providerID: .claude,
                startAt: at(tomorrow, hour: 10),
                durationSeconds: 5 * 3600,
                projectPath: "/Users/dev/projects/widget",
                status: .scheduled
            )
        ]
        let actualWindows: [ActualWindow] = [
            ActualWindow(
                providerID: .claude,
                startAt: at(today, hour: 9, minute: 7),
                durationSeconds: 5 * 3600,
                source: .c5hTriggered,
                confidence: .exact
            )
        ]

        for w in plannedWindows {
            try? await plannedRepository.create(w)
        }
        for w in actualWindows {
            try? await actualRepository.create(w)
        }
    }
}
#endif
