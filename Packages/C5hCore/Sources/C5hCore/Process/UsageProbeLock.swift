import Foundation
import Darwin

public struct UsageProbeLockConfiguration: Sendable {
    public var directory: URL?
    public var isEnabled: Bool

    public init(directory: URL? = nil, isEnabled: Bool = true) {
        self.directory = directory
        self.isEnabled = isEnabled
    }

    public static let disabled = UsageProbeLockConfiguration(isEnabled: false)

    public static var production: UsageProbeLockConfiguration {
        UsageProbeLockConfiguration(directory: nil, isEnabled: true)
    }
}

public final class UsageProbeLock: @unchecked Sendable {
    private let fd: Int32
    public let url: URL

    private init(fd: Int32, url: URL) {
        self.fd = fd
        self.url = url
    }

    deinit {
        _ = flock(fd, LOCK_UN)
        _ = close(fd)
    }

    public static func acquire(
        providerID: ProviderID,
        configuration: UsageProbeLockConfiguration = .production
    ) throws -> UsageProbeLock? {
        guard configuration.isEnabled else { return nil }

        let directory = try configuration.directory ?? defaultDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(providerID.rawValue).usage.lock")
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            throw C5hError.processLaunchFailed(errnoMessage("open usage lock failed"))
        }

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let lockErrno = errno
            _ = close(fd)
            if lockErrno == EWOULDBLOCK || lockErrno == EAGAIN {
                return nil
            }
            throw C5hError.processLaunchFailed(errnoMessage("flock usage lock failed", errnoValue: lockErrno))
        }

        let metadata = "pid=\(getpid()) startedAt=\(Date().ISO8601Format()) provider=\(providerID.rawValue)\n"
        _ = ftruncate(fd, 0)
        _ = metadata.withCString { write(fd, $0, strlen($0)) }
        _ = lseek(fd, 0, SEEK_SET)
        return UsageProbeLock(fd: fd, url: url)
    }

    private static func defaultDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support
            .appendingPathComponent("C5h", isDirectory: true)
            .appendingPathComponent("locks", isDirectory: true)
    }

    private static func errnoMessage(_ prefix: String, errnoValue: Int32 = errno) -> String {
        "\(prefix): \(String(cString: strerror(errnoValue)))"
    }
}
