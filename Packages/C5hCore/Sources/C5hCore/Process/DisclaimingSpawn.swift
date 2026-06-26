import Foundation
import Darwin

// Marks the spawned child as its own TCC responsible process so macOS attributes
// the child's filesystem access (Documents, Downloads, Photos, Music, etc.) to
// the child binary instead of to C5h.app / C5hHelper. Same SPI Chromium and
// Electron have used for years; declared in <sys/spawn.h> but not exported.
@_silgen_name("responsibility_spawnattrs_setdisclaim")
private func responsibility_spawnattrs_setdisclaim(
    _ attrs: UnsafeMutablePointer<posix_spawnattr_t?>,
    _ disclaim: Int32
) -> Int32

public enum StdioTarget: Sendable {
    case pipe
    case inherit
    case fileHandle(FileHandle)
    case devNull
}

public struct SpawnError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }

    public init(message: String) {
        self.message = message
    }
}

public final class LaunchedProcess: @unchecked Sendable {
    public let pid: pid_t
    public let stdinHandle: FileHandle?
    public let stdoutHandle: FileHandle?
    public let stderrHandle: FileHandle?

    private let condition = NSCondition()
    private var cachedExitCode: Int32?
    private var waitInProgress = false

    init(pid: pid_t, stdin: FileHandle?, stdout: FileHandle?, stderr: FileHandle?) {
        self.pid = pid
        self.stdinHandle = stdin
        self.stdoutHandle = stdout
        self.stderrHandle = stderr
    }

    public var isRunning: Bool {
        pollExitCode() == nil
    }

    public func terminate() {
        // Negative pid targets the entire process group (set via
        // POSIX_SPAWN_SETPGROUP at spawn) so orphaned grandchildren go too.
        _ = Darwin.kill(-pid, SIGTERM)
    }

    public func kill() {
        _ = Darwin.kill(-pid, SIGKILL)
    }

    public func wait() async -> Int32 {
        await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
            Task.detached(priority: .utility) {
                cont.resume(returning: self.waitBlocking())
            }
        }
    }

    public func waitBlocking() -> Int32 {
        condition.lock()
        if let cached = cachedExitCode {
            condition.unlock()
            return cached
        }

        while waitInProgress {
            condition.wait()
            if let cached = cachedExitCode {
                condition.unlock()
                return cached
            }
        }
        waitInProgress = true
        condition.unlock()

        var status: Int32 = 0
        let code: Int32
        while true {
            let r = waitpid(pid, &status, 0)
            if r == -1 {
                if errno == EINTR { continue }
                code = -1
                break
            }
            code = Self.decodeWaitStatus(status)
            break
        }

        condition.lock()
        cachedExitCode = code
        waitInProgress = false
        condition.broadcast()
        condition.unlock()
        return code
    }

    private func pollExitCode() -> Int32? {
        condition.lock()
        if let cached = cachedExitCode {
            condition.unlock()
            return cached
        }
        if waitInProgress {
            condition.unlock()
            return nil
        }
        waitInProgress = true
        condition.unlock()

        var status: Int32 = 0
        let result = waitpid(pid, &status, WNOHANG)
        let code: Int32?
        if result == pid {
            code = Self.decodeWaitStatus(status)
        } else if result == 0 || errno == EINTR {
            code = nil
        } else {
            code = -1
        }

        condition.lock()
        if let code {
            cachedExitCode = code
        }
        waitInProgress = false
        condition.broadcast()
        let cached = cachedExitCode
        condition.unlock()
        return cached
    }

    private static func decodeWaitStatus(_ status: Int32) -> Int32 {
        // Decode wait status. macOS macros aren't bridged to Swift.
        if (status & 0x7f) == 0 {
            return (status >> 8) & 0xff
        }
        return 128 + (status & 0x7f)
    }
}

public enum DisclaimingSpawn {
    public static func launch(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:],
        workingDirectory: URL? = nil,
        stdin: StdioTarget = .devNull,
        stdout: StdioTarget = .inherit,
        stderr: StdioTarget = .inherit
    ) throws -> LaunchedProcess {
        var attrs: posix_spawnattr_t?
        guard posix_spawnattr_init(&attrs) == 0 else {
            throw SpawnError(message: "posix_spawnattr_init failed (errno \(errno))")
        }
        defer { posix_spawnattr_destroy(&attrs) }
        try check(
            responsibility_spawnattrs_setdisclaim(&attrs, 1),
            "responsibility_spawnattrs_setdisclaim"
        )

        // Put the child in its own process group so SIGTERM on cancel/timeout
        // reaches subprocesses (e.g. bash's child `sleep`) instead of leaving
        // orphans that keep our stdout pipe open until they exit on their own.
        // Reset signal dispositions + unblock signals, otherwise the child
        // inherits whatever masks the parent (or test runner) had, which can
        // cause SIGTERM to be silently ignored.
        let flags: Int16 = Int16(POSIX_SPAWN_SETPGROUP)
            | Int16(POSIX_SPAWN_SETSIGDEF)
            | Int16(POSIX_SPAWN_SETSIGMASK)
        try check(posix_spawnattr_setflags(&attrs, flags), "posix_spawnattr_setflags")
        try check(posix_spawnattr_setpgroup(&attrs, 0), "posix_spawnattr_setpgroup")

        var allSignals = sigset_t()
        try check(sigfillset(&allSignals), "sigfillset")
        try check(posix_spawnattr_setsigdefault(&attrs, &allSignals), "posix_spawnattr_setsigdefault")

        var emptyMask = sigset_t()
        try check(sigemptyset(&emptyMask), "sigemptyset")
        try check(posix_spawnattr_setsigmask(&attrs, &emptyMask), "posix_spawnattr_setsigmask")

        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else {
            throw SpawnError(message: "posix_spawn_file_actions_init failed (errno \(errno))")
        }
        defer { posix_spawn_file_actions_destroy(&actions) }

        if let cwd = workingDirectory {
            let rc = cwd.path.withCString { posix_spawn_file_actions_addchdir_np(&actions, $0) }
            try check(rc, "addchdir for \(cwd.path)")
        }

        var pendingChildCloses: [Int32] = []
        var parentFDs: [Int32?] = [nil, nil, nil]

        func plan(_ target: StdioTarget, childFD: Int32, isReadEnd: Bool) throws {
            switch target {
            case .inherit:
                return
            case .devNull:
                let rc = "/dev/null".withCString { cstr in
                    posix_spawn_file_actions_addopen(
                        &actions, childFD, cstr,
                        isReadEnd ? O_RDONLY : O_WRONLY, 0
                    )
                }
                try check(rc, "addopen /dev/null fd \(childFD)")
            case .fileHandle(let handle):
                if handle.fileDescriptor == childFD {
                    return
                }
                let rc = posix_spawn_file_actions_adddup2(&actions, handle.fileDescriptor, childFD)
                try check(rc, "adddup2 fd \(childFD)")
            case .pipe:
                var fds: [Int32] = [-1, -1]
                let rc = fds.withUnsafeMutableBufferPointer { buf -> Int32 in
                    pipe(buf.baseAddress!)
                }
                if rc != 0 { throw SpawnError(message: "pipe() failed (errno \(errno))") }
                let childEnd = isReadEnd ? fds[0] : fds[1]
                let parentEnd = isReadEnd ? fds[1] : fds[0]
                do {
                    if childEnd != childFD {
                        try check(posix_spawn_file_actions_adddup2(&actions, childEnd, childFD), "adddup2 fd \(childFD)")
                        try check(posix_spawn_file_actions_addclose(&actions, childEnd), "addclose child pipe fd \(childEnd)")
                    }
                    try check(posix_spawn_file_actions_addclose(&actions, parentEnd), "addclose parent pipe fd \(parentEnd)")
                } catch {
                    close(childEnd)
                    close(parentEnd)
                    throw error
                }
                pendingChildCloses.append(childEnd)
                parentFDs[Int(childFD)] = parentEnd
            }
        }

        do {
            try plan(stdin, childFD: 0, isReadEnd: true)
            try plan(stdout, childFD: 1, isReadEnd: false)
            try plan(stderr, childFD: 2, isReadEnd: false)
        } catch {
            for fd in pendingChildCloses { close(fd) }
            for fd in parentFDs.compactMap({ $0 }) { close(fd) }
            throw error
        }

        let argv = [executableURL.path] + arguments
        let resolvedEnv = environment.isEmpty
            ? EnvironmentResolver.defaultEnvironment()
            : environment
        let envPairs = resolvedEnv.map { "\($0.key)=\($0.value)" }

        var pid: pid_t = 0
        let spawnRC = withCStringArray(argv) { argvC in
            withCStringArray(envPairs) { envC in
                executableURL.path.withCString { exePath in
                    posix_spawn(&pid, exePath, &actions, &attrs, argvC, envC)
                }
            }
        }

        // Parent always closes the child-side ends of any pipes it created;
        // they live on inside the child via the file-action dup2.
        for fd in pendingChildCloses { close(fd) }

        guard spawnRC == 0 else {
            for fd in parentFDs.compactMap({ $0 }) { close(fd) }
            throw SpawnError(message: "posix_spawn failed (\(spawnRC)) for \(executableURL.path)")
        }

        let stdinH  = parentFDs[0].map { FileHandle(fileDescriptor: $0, closeOnDealloc: true) }
        let stdoutH = parentFDs[1].map { FileHandle(fileDescriptor: $0, closeOnDealloc: true) }
        let stderrH = parentFDs[2].map { FileHandle(fileDescriptor: $0, closeOnDealloc: true) }

        return LaunchedProcess(
            pid: pid,
            stdin: stdinH,
            stdout: stdoutH,
            stderr: stderrH
        )
    }
}

private func check(_ result: Int32, _ operation: String) throws {
    guard result == 0 else {
        throw SpawnError(message: "\(operation) failed (\(result))")
    }
}

private func withCStringArray<T>(
    _ strings: [String],
    _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) throws -> T
) rethrows -> T {
    var cStrings: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
    cStrings.append(nil)
    defer {
        for ptr in cStrings where ptr != nil { free(ptr) }
    }
    return try cStrings.withUnsafeBufferPointer { buf in
        try body(buf.baseAddress!)
    }
}
