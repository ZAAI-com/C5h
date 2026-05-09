import Foundation
import Observation

@Observable
@MainActor
final class AppEnvironment {
    var isReady: Bool = true
}
