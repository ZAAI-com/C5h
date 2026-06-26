import Foundation

/// Resolves the app marketing version a helper should report in heartbeats.
public enum HelperAppVersion {
    public static let environmentKey = "C5H_APP_VERSION"
    public static let unknown = "unknown"

    private static let shortVersionKey = "CFBundleShortVersionString"

    public static func version(
        forHelperAt helperExecutableURL: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let version = normalized(environment[environmentKey]) {
            return version
        }

        guard let appBundleURL = containingAppBundle(for: helperExecutableURL) else {
            return unknown
        }

        let infoPlistURL = appBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        return version(fromInfoPlistAt: infoPlistURL) ?? unknown
    }

    public static func version(from bundle: Bundle) -> String? {
        normalized(bundle.object(forInfoDictionaryKey: shortVersionKey) as? String)
    }

    private static func containingAppBundle(for url: URL) -> URL? {
        var current = url.standardizedFileURL
        while current.path != "/" {
            if current.pathExtension == "app" {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
        return nil
    }

    private static func version(fromInfoPlistAt url: URL) -> String? {
        guard
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        else {
            return nil
        }
        return normalized(plist[shortVersionKey] as? String)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
