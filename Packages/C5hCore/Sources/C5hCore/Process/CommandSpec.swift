import Foundation

public struct CommandSpec: Sendable {
    public var providerID: ProviderID
    public var commandName: CommandName
    public var executableURL: URL
    public var arguments: [String]
    public var workingDirectory: URL?
    public var environment: [String: String]
    public var timeoutSeconds: TimeInterval
    public var toolVersion: String?

    public init(
        providerID: ProviderID,
        commandName: CommandName,
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String] = [:],
        timeoutSeconds: TimeInterval = 300,
        toolVersion: String? = nil
    ) {
        self.providerID = providerID
        self.commandName = commandName
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
        self.toolVersion = toolVersion
    }

    public func argumentsJSON() -> String {
        (try? String(data: JSONEncoder().encode(arguments), encoding: .utf8)) ?? "[]"
    }
}
