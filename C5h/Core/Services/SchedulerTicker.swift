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
        let interval = tickInterval
        task = Task { [weak self] in
            while !Task.isCancelled {
                let report = await scheduler.tick(now: .now)
                await MainActor.run {
                    self?.lastReport = report
                    self?.lastError = report.lastError
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
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
