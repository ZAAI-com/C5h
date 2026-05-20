import SwiftUI

enum C5hAnimation {
    static let morph: Animation = .spring(response: 0.45, dampingFraction: 0.82)

    static let flick: Animation = .spring(response: 0.28, dampingFraction: 0.78)

    static let settle: Animation = .spring(response: 0.6, dampingFraction: 0.92)
}
