import SwiftUI

struct PlaceholderScreen: View {
    let title: String
    let systemImage: String
    let subtitle: String

    var body: some View {
        VStack(spacing: C5hSpacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(C5hColors.fgTertiary)
            VStack(spacing: C5hSpacing.xs) {
                Text(title)
                    .font(C5hTypography.titleFont)
                    .foregroundStyle(C5hColors.foreground)
                Text(subtitle)
                    .font(C5hTypography.bodyFont)
                    .foregroundStyle(C5hColors.fgSecondary)
                    .multilineTextAlignment(.center)
            }
            Text("Coming in a later milestone.")
                .font(C5hTypography.captionFont)
                .foregroundStyle(C5hColors.fgTertiary)
        }
        .padding(C5hSpacing.xxl)
        .frame(maxWidth: 520)
        // LEVEL 2 — first-impression hero panel; transient overlay-like
        // surface, glass treatment is appropriate per HIG.
        .glassEffect(C5hGlass.heroPanel, in: C5hShape.rect(C5hRadius.xl))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    PlaceholderScreen(
        title: "Dashboard",
        systemImage: "chart.xyaxis.line",
        subtitle: "Quick overview of provider activity."
    )
    .frame(width: 800, height: 500)
}
