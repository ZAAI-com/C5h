import Foundation

/// Deterministic build identity for the background helper, derived from the
/// helper binary's modification time. It lets the app detect when the *running*
/// helper process is older than the binary on disk (e.g. rebuilt during
/// development but never restarted), a state that otherwise fails silently
/// (the running process keeps executing stale code).
public enum HelperBuildStamp {
    public static let baseVersion = "0.0.1"

    /// Version string the helper records in its heartbeat, e.g.
    /// `"0.0.1+1719421127"`. The suffix is the binary's modification time, so a
    /// rebuild changes it. Falls back to `baseVersion` when the binary can't be
    /// stat'd.
    public static func version(
        forBinaryAt url: URL,
        fileManager: FileManager = .default
    ) -> String {
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: url.path),
            let modified = attributes[.modificationDate] as? Date
        else {
            return baseVersion
        }
        return "\(baseVersion)+\(Int(modified.timeIntervalSince1970))"
    }
}
