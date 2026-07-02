import Foundation
import Testing
@testable import C5hCore

@Suite("CLIPathResolver")
struct CLIPathResolverTests {
    @Test("Configured path is preferred when executable")
    func configuredPath() async throws {
        let dir = try TempDirectory.make()
        defer { try? TempDirectory.cleanup(dir) }
        let executable = dir.appendingPathComponent("ok-tool")
        FileManager.default.createFile(
            atPath: executable.path,
            contents: "#!/bin/sh\nexit 0\n".data(using: .utf8)
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let resolver = DefaultCLIPathResolver()
        let resolved = await resolver.resolveCLI(
            named: "ok-tool",
            configuredPath: executable.path
        )
        #expect(resolved?.path == executable.path)
    }

    @Test("Search prefixes prefer user local bin before Homebrew")
    func prefersUserLocalBeforeHomebrew() async throws {
        let dir = try TempDirectory.make()
        defer { try? TempDirectory.cleanup(dir) }
        let userLocal = dir.appendingPathComponent("user-local", isDirectory: true)
        let homebrew = dir.appendingPathComponent("homebrew", isDirectory: true)
        try FileManager.default.createDirectory(at: userLocal, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homebrew, withIntermediateDirectories: true)
        let userClaude = try makeExecutable(named: "claude", in: userLocal)
        _ = try makeExecutable(named: "claude", in: homebrew)

        let resolver = DefaultCLIPathResolver(
            searchPrefixes: [userLocal.path, homebrew.path],
            whichExecutable: dir.appendingPathComponent("missing-which")
        )
        let resolved = await resolver.resolveCLI(named: "claude", configuredPath: nil)
        #expect(resolved?.path == userClaude.path)
    }

    @Test("Unknown tool resolves to nil")
    func unknownTool() async {
        let resolver = DefaultCLIPathResolver()
        let resolved = await resolver.resolveCLI(
            named: "definitely-not-a-real-binary-xyz-123",
            configuredPath: nil
        )
        #expect(resolved == nil)
    }

    @Test("which fallback finds /usr/bin/which itself")
    func whichFallback() async {
        let resolver = DefaultCLIPathResolver()
        let resolved = await resolver.resolveCLI(named: "which", configuredPath: nil)
        // 'which' may live at /usr/bin/which (matching knownPrefixes) — either is fine
        #expect(resolved != nil)
    }

    private func makeExecutable(named name: String, in directory: URL) throws -> URL {
        let executable = directory.appendingPathComponent(name)
        FileManager.default.createFile(
            atPath: executable.path,
            contents: "#!/bin/sh\nexit 0\n".data(using: .utf8)
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        return executable
    }
}

@Suite("EnvironmentResolver")
struct EnvironmentResolverTests {
    @Test("PATH override is applied")
    func pathOverride() {
        let env = EnvironmentResolver.defaultEnvironment(baseEnvironment: ["FOO": "bar"])
        #expect(env["PATH"] == EnvironmentResolver.defaultPath)
        #expect(env["FOO"] == "bar")
    }

    @Test("Sensitive names are detected")
    func sensitiveDetection() {
        #expect(EnvironmentResolver.isSensitive(name: "AWS_SECRET_KEY") == true)
        #expect(EnvironmentResolver.isSensitive(name: "API_TOKEN") == true)
        #expect(EnvironmentResolver.isSensitive(name: "OPENAI_API_KEY") == true)
        #expect(EnvironmentResolver.isSensitive(name: "USER_PASSWORD") == true)
        #expect(EnvironmentResolver.isSensitive(name: "PATH") == false)
        #expect(EnvironmentResolver.isSensitive(name: "HOME") == false)
    }

    @Test("Redaction replaces sensitive values")
    func redaction() {
        let input = ["PATH": "/usr/bin", "API_TOKEN": "abc123", "HOME": "/users/m"]
        let redacted = EnvironmentResolver.redactedForLogging(input)
        #expect(redacted["PATH"] == "/usr/bin")
        #expect(redacted["HOME"] == "/users/m")
        #expect(redacted["API_TOKEN"] == "<redacted>")
    }
}
