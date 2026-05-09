import SwiftUI

enum C5hColors {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let chrome = Color(nsColor: .underPageBackgroundColor)
    static let foreground = Color(nsColor: .labelColor)
    static let fgSecondary = Color(nsColor: .secondaryLabelColor)
    static let fgTertiary = Color(nsColor: .tertiaryLabelColor)
    static let separator = Color(nsColor: .separatorColor)

    static let accent = Color(red: 0.85, green: 0.43, blue: 0.25)
    static let accentMuted = Color(red: 0.85, green: 0.43, blue: 0.25, opacity: 0.14)
}

enum ProviderBrandColor {
    static let claude = Color(red: 0.85, green: 0.43, blue: 0.25)
    static let codex = Color(red: 0.15, green: 0.39, blue: 0.92)
}

#Preview {
    HStack(spacing: 12) {
        swatch("Claude", ProviderBrandColor.claude)
        swatch("Codex", ProviderBrandColor.codex)
        swatch("Accent", C5hColors.accent)
    }
    .padding(40)
}

@MainActor
private func swatch(_ label: String, _ color: Color) -> some View {
    VStack(spacing: 8) {
        RoundedRectangle(cornerRadius: 8).fill(color).frame(width: 80, height: 80)
        Text(label).font(.caption)
    }
}
