import SwiftUI

struct SettingsView: View {
    var body: some View {
        PlaceholderScreen(
            title: "Settings",
            systemImage: AppTab.settings.systemImage,
            subtitle: "General, scheduler, providers, logs, advanced."
        )
    }
}

#Preview {
    SettingsView()
        .frame(width: 760, height: 540)
}
