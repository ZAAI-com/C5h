import SwiftUI

/// Liquid Glass roles for C5h. Glass belongs on the navigation layer
/// (toolbars, sheets, popovers, menus, the inspector pane, transient
/// overlays). Levels:
///
/// - Level 1 (HIG-correct): only `toolbar`. Content uses `Material`.
/// - Level 2: + `chip`, `heroPanel` for floating chips and hero panels.
/// - Level 3 (HIG-warning): + `card` for full-glass content cards.
enum C5hGlass {
    static let toolbar: Glass = .regular

    static let heroPanel: Glass = .regular

    static func chip(tint: Color) -> Glass {
        .regular.tint(tint.opacity(0.18))
    }

    static func card(tint: Color? = nil) -> Glass {
        if let tint {
            return .regular.tint(tint.opacity(0.10))
        }
        return .regular
    }
}
