import SwiftUI

struct ProvidersView: View {
    var body: some View {
        PlaceholderScreen(
            title: "Providers",
            systemImage: AppTab.providers.systemImage,
            subtitle: "Detect Claude Code and OpenAI Codex CLIs and configure paths."
        )
    }
}

#Preview {
    ProvidersView()
        .frame(width: 1100, height: 700)
}
