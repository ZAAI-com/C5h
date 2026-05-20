import SwiftUI
import C5hCore

struct ProviderStatusBadge: View {
    let state: ProviderHealthState

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(C5hTypography.captionFont)
                .foregroundStyle(C5hColors.foreground)
        }
        .padding(.horizontal, C5hSpacing.sm)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(0.12))
        )
    }

    private var color: Color {
        switch state {
        case .unknown: .gray
        case .ready: .green
        case .cliMissing: .orange
        case .authMissing: .yellow
        case .error: .red
        }
    }

    private var label: String { state.label }
}
