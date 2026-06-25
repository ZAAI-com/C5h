import Darwin

enum ProcessLivenessChecker {
    static func isAlive(pid: Int) -> Bool {
        guard pid > 0 else { return false }

        let result = kill(pid_t(pid), 0)
        if result == 0 {
            return true
        }

        switch errno {
        case EPERM:
            return true
        case ESRCH:
            return false
        default:
            return false
        }
    }
}
