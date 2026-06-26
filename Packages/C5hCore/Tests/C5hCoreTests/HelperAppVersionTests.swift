import Foundation
import Testing
@testable import C5hCore

@Suite("HelperAppVersion")
struct HelperAppVersionTests {
    @Test("Environment override returns exact app version")
    func environmentOverrideReturnsExactVersion() {
        let version = HelperAppVersion.version(
            forHelperAt: URL(fileURLWithPath: "/tmp/C5hHelper"),
            environment: [HelperAppVersion.environmentKey: " 1.0.0 \n"]
        )

        #expect(version == "1.0.0")
    }

    @Test("Bundled helper reads containing app Info.plist")
    func bundledHelperReadsContainingAppInfoPlist() throws {
        let dir = try TempDirectory.make()
        defer { try? TempDirectory.cleanup(dir) }

        let contents = dir
            .appendingPathComponent("C5h.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
        let helpers = contents.appendingPathComponent("Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleShortVersionString": "1.0.0"],
            format: .xml,
            options: 0
        )
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))

        let helperURL = helpers.appendingPathComponent("C5hHelper")
        FileManager.default.createFile(atPath: helperURL.path, contents: Data())

        let version = HelperAppVersion.version(forHelperAt: helperURL, environment: [:])

        #expect(version == "1.0.0")
    }

    @Test("Missing environment and app bundle returns unknown")
    func missingEnvironmentAndBundleReturnsUnknown() {
        let version = HelperAppVersion.version(
            forHelperAt: URL(fileURLWithPath: "/tmp/C5hHelper"),
            environment: [:]
        )

        #expect(version == HelperAppVersion.unknown)
    }
}
