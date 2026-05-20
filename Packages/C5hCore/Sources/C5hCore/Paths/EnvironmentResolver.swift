import Foundation

public enum EnvironmentResolver {
    public static let defaultPath: String = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ].joined(separator: ":")

    public static let sensitivePattern: NSRegularExpression = {
        // intentional force-try: pattern is constant
        try! NSRegularExpression(
            pattern: "TOKEN|KEY|SECRET|PASSWORD|PASSWD",
            options: [.caseInsensitive]
        )
    }()

    public static func defaultEnvironment(
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        overridePath: String? = nil
    ) -> [String: String] {
        var env = baseEnvironment
        env["PATH"] = overridePath ?? defaultPath
        return env
    }

    public static func redactedForLogging(_ env: [String: String]) -> [String: String] {
        env.reduce(into: [String: String]()) { acc, pair in
            if isSensitive(name: pair.key) {
                acc[pair.key] = "<redacted>"
            } else {
                acc[pair.key] = pair.value
            }
        }
    }

    public static func isSensitive(name: String) -> Bool {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return sensitivePattern.firstMatch(in: name, options: [], range: range) != nil
    }
}
