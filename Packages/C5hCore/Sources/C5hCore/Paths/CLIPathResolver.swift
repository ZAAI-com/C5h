import Foundation

public protocol CLIPathResolving: Sendable {
    func resolveCLI(named executableName: String, configuredPath: String?) async -> URL?
}

public struct DefaultCLIPathResolver: CLIPathResolving {
    public static var defaultKnownPrefixes: [String] {
        [
            "\(NSHomeDirectory())/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
    }

    public static var knownPrefixes: [String] { defaultKnownPrefixes }

    private let searchPrefixes: [String]
    private let whichExecutable: URL

    public init(
        searchPrefixes: [String] = Self.defaultKnownPrefixes,
        whichExecutable: URL = URL(fileURLWithPath: "/usr/bin/which")
    ) {
        self.searchPrefixes = searchPrefixes
        self.whichExecutable = whichExecutable
    }

    public func resolveCLI(named executableName: String, configuredPath: String?) async -> URL? {
        let fm = FileManager.default
        if let configured = configuredPath, !configured.isEmpty {
            let url = URL(fileURLWithPath: configured)
            if fm.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        for prefix in searchPrefixes {
            let candidate = URL(fileURLWithPath: prefix).appendingPathComponent(executableName)
            if fm.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return await whichLookup(executableName)
    }

    private func whichLookup(_ name: String) async -> URL? {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: whichExecutable.path) else {
            return nil
        }

        let launched: LaunchedProcess
        do {
            launched = try DisclaimingSpawn.launch(
                executableURL: whichExecutable,
                arguments: [name],
                environment: EnvironmentResolver.defaultEnvironment(),
                stdout: .pipe,
                stderr: .devNull
            )
        } catch {
            return nil
        }
        defer { try? launched.stdoutHandle?.close() }

        let exitCode = await launched.wait()
        guard exitCode == 0 else { return nil }
        let data = launched.stdoutHandle?.readDataToEndOfFile() ?? Data()
        guard
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else {
            return nil
        }
        let url = URL(fileURLWithPath: raw)
        return fm.isExecutableFile(atPath: url.path) ? url : nil
    }
}
