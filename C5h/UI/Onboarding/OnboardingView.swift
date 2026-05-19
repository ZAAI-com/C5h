import SwiftUI
import C5hStore

struct OnboardingView: View {
    let onFinish: () -> Void
    private let appSettings: (any AppSettingsRepository)?

    init(appSettings: (any AppSettingsRepository)? = nil, onFinish: @escaping () -> Void) {
        self.appSettings = appSettings
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            Color.clear
                .background(.background)
                .ignoresSafeArea()

            heroPanel
                .frame(maxWidth: 560)
                .padding(C5hSpacing.xxl)
        }
    }

    private var heroPanel: some View {
        // LEVEL 2 — first-launch hero. Glass panel + glassProminent CTA.
        VStack(spacing: C5hSpacing.lg) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(C5hColors.accentOnGlass)

            VStack(spacing: C5hSpacing.sm) {
                Text("Welcome to C5h")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Track Claude and Codex 5-hour windows in one place.")
                    .font(C5hTypography.bodyFont)
                    .foregroundStyle(C5hColors.fgSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: C5hSpacing.md) {
                bulletRow(icon: "calendar.day.timeline.left", text: "See active windows on the day calendar")
                bulletRow(icon: "shippingbox", text: "Connect Claude and Codex CLIs")
                bulletRow(icon: "chart.xyaxis.line", text: "Watch usage trends over time")
            }
            .padding(.vertical, C5hSpacing.sm)

            HStack(spacing: C5hSpacing.md) {
                Button("Skip") { finish() }
                    .buttonStyle(.glass)

                Button("Get started") { finish() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(C5hSpacing.xxl)
        .glassEffect(C5hGlass.heroPanel, in: C5hShape.rect(C5hRadius.xl))
    }

    private func bulletRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: C5hSpacing.md) {
            Image(systemName: icon)
                .foregroundStyle(C5hColors.accentOnGlass)
                .frame(width: 20)
            Text(text)
                .font(C5hTypography.bodyFont)
                .foregroundStyle(C5hColors.foreground)
            Spacer(minLength: 0)
        }
    }

    private func finish() {
        if let appSettings {
            Task {
                try? await appSettings.set(OnboardingView.completedKey, value: true)
            }
        }
        onFinish()
    }

    static let completedKey = "hasCompletedOnboarding"

    static func shouldShow(appSettings: any AppSettingsRepository) async -> Bool {
        let done: Bool? = try? await appSettings.get(completedKey, as: Bool.self)
        return done != true
    }
}

#Preview {
    OnboardingView { }
        .frame(width: 1200, height: 800)
}
