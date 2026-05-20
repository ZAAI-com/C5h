import Foundation
import Observation
import C5hCore

@Observable
@MainActor
final class SchedulerTicker {
    let scheduler: SchedulerService
    private(set) var isRunning: Bool = false
    private(set) var lastReport: SchedulerTickReport?
    private(set) var lastError: String?
    var tickInterval: TimeInterval

    private var task: Task<Void, Never>?

    init(scheduler: SchedulerService, tickInterval: TimeInterval = 30) {
        self.scheduler = scheduler
        self.tickInterval = tickInterval
    }

    func start() {
        guard task == nil else { return }
        isRunning = true
        let scheduler = scheduler
        task = Task { [weak self] in
            while !Task.isCancelled {
                let report = await scheduler.tick(now: .now)
                let interval = await MainActor.run { () -> TimeInterval in
                    self?.lastReport = report
                    self?.lastError = report.lastError
                    return self?.tickInterval ?? 30
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func runOnceNow() async {
        let report = await scheduler.tick(now: .now)
        lastReport = report
        lastError = report.lastError
    }
}
