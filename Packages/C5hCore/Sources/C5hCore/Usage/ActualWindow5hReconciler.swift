import Foundation

/// Cleans up stale `c5hTriggered` placeholder 5h windows.
///
/// When a triggered run fires while upstream usage is unavailable,
/// `ActiveWindowResolver` used to pin an estimated `[trigger, +5h]` placeholder.
/// If the trigger landed inside an already-active window, that placeholder is
/// offset from the real `detectedFromUsage` window (its end differs by more than
/// the dedup tolerance), so `upsertByEndAt` never merged it and it lingers as a
/// duplicate calendar block. This reconciler collapses each such placeholder onto
/// its overlapping real window, leaving the single-row state the trigger should
/// have produced.
///
/// Pure and side-effect free: it returns the actions to apply so the persistence
/// layer can run them and so the logic stays unit-testable.
public enum ActualWindow5hReconciler {
    /// One reconciliation action: keep `survivor` (the real detected window,
    /// promoted to carry the placeholder's command link) and delete `phantomID`.
    public struct Resolution: Sendable, Equatable {
        public let survivor: ActualWindow5h
        public let phantomID: UUID

        public init(survivor: ActualWindow5h, phantomID: UUID) {
            self.survivor = survivor
            self.phantomID = phantomID
        }
    }

    /// Returns the placeholders to collapse. `tolerance` mirrors the upsert dedup
    /// tolerance: only placeholders whose end is further than `tolerance` from the
    /// real window's end are treated as phantoms (a within-tolerance placeholder
    /// would already have merged).
    public static func resolve(
        windows: [ActualWindow5h],
        tolerance: TimeInterval = 60
    ) -> [Resolution] {
        let detected = windows.filter { $0.source == .detectedFromUsage }
        guard !detected.isEmpty else { return [] }

        var resolutions: [Resolution] = []
        for phantom in windows where isPhantom(phantom) {
            guard let real = detected.first(where: { real in
                real.providerID == phantom.providerID
                    && real.startAt < phantom.endAt
                    && phantom.startAt < real.endAt
                    && abs(real.endAt.timeIntervalSince(phantom.endAt)) > tolerance
            }) else { continue }

            var survivor = real
            survivor.source = .c5hTriggered
            if survivor.commandRunID == nil {
                survivor.commandRunID = phantom.commandRunID
            }
            resolutions.append(Resolution(survivor: survivor, phantomID: phantom.id))
        }
        return resolutions
    }

    /// A pinned trigger placeholder: estimated `c5hTriggered` with no usage
    /// snapshot links. Windows promoted from real usage carry snapshot links and
    /// are never treated as phantoms.
    private static func isPhantom(_ window: ActualWindow5h) -> Bool {
        window.source == .c5hTriggered
            && window.confidence == .estimated
            && window.usageStartSnapshotID == nil
            && window.usageEndSnapshotID == nil
    }
}
