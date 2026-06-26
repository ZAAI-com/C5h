import Foundation

/// Metadata for the on-disk helper binary. The app uses this to detect when a
/// running debug helper predates the executable that would be launched now.
public enum HelperBuildStamp {
    public static func modificationDate(
        forBinaryAt url: URL,
        fileManager: FileManager = .default
    ) -> Date? {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }
}
