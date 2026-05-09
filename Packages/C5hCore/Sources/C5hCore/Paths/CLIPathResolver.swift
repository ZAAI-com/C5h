import Foundation

public protocol CLIPathResolving: Sendable {
    func resolveCLI(named executableName: String, configuredPath: String?) async -> URL?
}

public struct DefaultCLIPathResolver: CLIPathResolving {
    public static let knownPrefixes: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin"
    ]

    private let whichExecutable: URL

    public init(whichExecutable: URL = URL(fileURLWithPath: "/usr/bin/which")) {
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

        for prefix in Self.knownPrefixes {
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
        let process = Process()
        process.executableURL = whichExecutable
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.environment = EnvironmentResolver.defaultEnvironment()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
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
