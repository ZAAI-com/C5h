import Foundation

public struct LogRetentionPolicy: Sendable, Hashable {
    public var maxAgeSeconds: TimeInterval
    public init(maxAgeSeconds: TimeInterval) {
        self.maxAgeSeconds = maxAgeSeconds
    }

    public static let sevenDays = LogRetentionPolicy(maxAgeSeconds: 7 * 86_400)
    public static let thirtyDays = LogRetentionPolicy(maxAgeSeconds: 30 * 86_400)
    public static let ninetyDays = LogRetentionPolicy(maxAgeSeconds: 90 * 86_400)
}

public struct LogRetentionResult: Sendable {
    public let removedFileCount: Int
    public let freedBytes: Int
}

public enum LogRetentionSweeper {
    public static func sweep(
        directory: URL,
        policy: LogRetentionPolicy,
        now: Date = .now
    ) throws -> LogRetentionResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else {
            return LogRetentionResult(removedFileCount: 0, freedBytes: 0)
        }
        var removed = 0
        var freed = 0
        let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [
                .contentModificationDateKey, .fileSizeKey, .isRegularFileKey
            ])
            guard values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) > policy.maxAgeSeconds else {
                continue
            }
            let size = values.fileSize ?? 0
            do {
                try fm.removeItem(at: url)
                removed += 1
                freed += size
            } catch {
                continue
            }
        }
        return LogRetentionResult(removedFileCount: removed, freedBytes: freed)
    }
}
