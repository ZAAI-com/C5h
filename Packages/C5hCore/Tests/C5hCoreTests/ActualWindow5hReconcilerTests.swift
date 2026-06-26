import Foundation
import Testing
@testable import C5hCore

@Suite("ActualWindow5hReconciler")
struct ActualWindow5hReconcilerTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func window(
        offset: TimeInterval,
        source: ActualWindowSource,
        confidence: WindowConfidence,
        commandRunID: UUID? = nil,
        usageStartSnapshotID: UUID? = nil,
        usageEndSnapshotID: UUID? = nil,
        provider: ProviderID = .claude
    ) -> ActualWindow5h {
        ActualWindow5h(
            providerID: provider,
            startAt: base.addingTimeInterval(offset),
            source: source,
            confidence: confidence,
            commandRunID: commandRunID,
            usageStartSnapshotID: usageStartSnapshotID,
            usageEndSnapshotID: usageEndSnapshotID
        )
    }

    @Test("Collapses a mid-window pinned placeholder onto its real detected window")
    func collapsesPhantom() throws {
        let cmd = UUID()
        let detected = window(offset: 0, source: .detectedFromUsage, confidence: .estimated)
        // Pinned 50 min into the active window: end is offset by 3000s (> tolerance).
        let phantom = window(
            offset: 3000,
            source: .c5hTriggered,
            confidence: .estimated,
            commandRunID: cmd
        )

        let resolutions = ActualWindow5hReconciler.resolve(windows: [detected, phantom])

        #expect(resolutions.count == 1)
        let resolution = try #require(resolutions.first)
        #expect(resolution.phantomID == phantom.id)
        #expect(resolution.survivor.id == detected.id)
        #expect(resolution.survivor.source == .c5hTriggered)
        // The detected window had no command link, so it inherits the placeholder's.
        #expect(resolution.survivor.commandRunID == cmd)
    }

    @Test("Keeps the detected window's own command link instead of the placeholder's")
    func keepsExistingCommandLink() throws {
        let detectedCmd = UUID()
        let phantomCmd = UUID()
        let detected = window(
            offset: 0,
            source: .detectedFromUsage,
            confidence: .estimated,
            commandRunID: detectedCmd
        )
        let phantom = window(
            offset: 3000,
            source: .c5hTriggered,
            confidence: .estimated,
            commandRunID: phantomCmd
        )

        let resolutions = ActualWindow5hReconciler.resolve(windows: [detected, phantom])

        let resolution = try #require(resolutions.first)
        #expect(resolution.survivor.commandRunID == detectedCmd)
    }

    @Test("Leaves two distinct detected reset windows untouched")
    func leavesDistinctDetectedWindows() {
        let first = window(offset: 0, source: .detectedFromUsage, confidence: .estimated)
        let second = window(offset: 3000, source: .detectedFromUsage, confidence: .estimated)

        let resolutions = ActualWindow5hReconciler.resolve(windows: [first, second])

        #expect(resolutions.isEmpty)
    }

    @Test("Leaves a triggered window with usage snapshot links untouched")
    func leavesPromotedWindow() {
        let detected = window(offset: 0, source: .detectedFromUsage, confidence: .estimated)
        // A genuinely promoted window carries snapshot links, so it is not a phantom.
        let promoted = window(
            offset: 3000,
            source: .c5hTriggered,
            confidence: .exact,
            commandRunID: UUID(),
            usageStartSnapshotID: UUID()
        )

        let resolutions = ActualWindow5hReconciler.resolve(windows: [detected, promoted])

        #expect(resolutions.isEmpty)
    }

    @Test("Leaves a placeholder whose end matches the detected window within tolerance")
    func leavesWithinTolerancePlaceholder() {
        let detected = window(offset: 0, source: .detectedFromUsage, confidence: .estimated)
        // Offset 30s: end is within the 60s dedup tolerance, so it would have merged.
        let placeholder = window(
            offset: 30,
            source: .c5hTriggered,
            confidence: .estimated,
            commandRunID: UUID()
        )

        let resolutions = ActualWindow5hReconciler.resolve(windows: [detected, placeholder])

        #expect(resolutions.isEmpty)
    }

    @Test("Does not collapse across providers or non-overlapping windows")
    func respectsProviderAndOverlap() {
        let detected = window(offset: 0, source: .detectedFromUsage, confidence: .estimated)
        // Same time, different provider.
        let otherProvider = window(
            offset: 3000,
            source: .c5hTriggered,
            confidence: .estimated,
            commandRunID: UUID(),
            provider: .codex
        )
        // Same provider but starts after the detected window ends (no overlap).
        let nonOverlapping = window(
            offset: 18_000 + 600,
            source: .c5hTriggered,
            confidence: .estimated,
            commandRunID: UUID()
        )

        let resolutions = ActualWindow5hReconciler.resolve(
            windows: [detected, otherProvider, nonOverlapping]
        )

        #expect(resolutions.isEmpty)
    }
}
