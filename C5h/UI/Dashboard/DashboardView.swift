import SwiftUI

struct DashboardView: View {
    var body: some View {
        PlaceholderScreen(
            title: "Dashboard",
            systemImage: AppTab.dashboard.systemImage,
            subtitle: "Active windows, next scheduled prompt, recent runs."
        )
    }
}

#Preview {
    DashboardView()
        .frame(width: 1100, height: 700)
}
