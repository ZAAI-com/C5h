import Foundation
import C5hCore

@MainActor
final class DebugBundleExporter {
    let appPaths: AppPaths

    init(appPaths: AppPaths) {
        self.appPaths = appPaths
    }

    /// Produces a zip at the given destination containing:
    ///   - the SQLite database file (snapshot copy)
    ///   - the latest 7 days of command-run stdout/stderr files
    ///   - a small manifest describing app/system info
    func export(to destination: URL) async throws {
        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5h-debug-\(UUID().uuidString)", isDirectory: true)
        let staging = stagingRoot.appendingPathComponent("c5h-debug-bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        // Manifest
        let manifest: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "bundleId": Bundle.main.bundleIdentifier ?? "unknown",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try manifestData.write(to: staging.appendingPathComponent("manifest.json"))

        // Database snapshot
        let dbCopy = staging.appendingPathComponent("c5h.sqlite")
        try? FileManager.default.copyItem(at: appPaths.databaseURL, to: dbCopy)

        // Recent logs
        let logsDest = staging.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDest, withIntermediateDirectories: true)
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        if let enumerator = FileManager.default.enumerator(
            at: appPaths.commandRunsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            while let url = enumerator.nextObject() as? URL {
                let values = try url.resourceValues(forKeys: [
                    .contentModificationDateKey, .isRegularFileKey
                ])
                guard values.isRegularFile == true,
                      let modified = values.contentModificationDate,
                      modified >= cutoff
                else { continue }
                let dest = logsDest.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: dest)
            }
        }

        // Zip via /usr/bin/zip (always available on macOS)
        let zipURL = stagingRoot.appendingPathComponent("c5h-debug-bundle.zip")
        let process = try DisclaimingSpawn.launch(
            executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-r", "-q", zipURL.path, "c5h-debug-bundle"],
            workingDirectory: stagingRoot,
            stdout: .devNull,
            stderr: .devNull
        )
        let exitCode = await process.wait()
        guard exitCode == 0 else {
            throw NSError(
                domain: "DebugBundleExporter",
                code: Int(exitCode),
                userInfo: [NSLocalizedDescriptionKey: "zip exited \(exitCode)"]
            )
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: zipURL, to: destination)
        try? FileManager.default.removeItem(at: stagingRoot)
    }
}
