import SwiftUI

struct NavbarView: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: C5hSpacing.lg) {
            logo
            Spacer(minLength: 0)
            tabBar
            Spacer(minLength: 0)
            trailingStatus
        }
        .padding(.horizontal, C5hSpacing.lg)
        .padding(.vertical, C5hSpacing.md)
        .frame(height: 56)
        .background(C5hColors.chrome)
    }

    private var logo: some View {
        HStack(spacing: C5hSpacing.sm) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(C5hColors.accent)
            Text("C5h")
                .font(C5hTypography.logoFont)
                .foregroundStyle(C5hColors.foreground)
        }
        .frame(minWidth: 96, alignment: .leading)
    }

    private var tabBar: some View {
        HStack(spacing: C5hSpacing.xs) {
            ForEach(AppTab.allCases.filter { $0 != .settings }) { tab in
                NavbarTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    action: { selectedTab = tab }
                )
            }
        }
    }

    private var trailingStatus: some View {
        HStack(spacing: C5hSpacing.sm) {
            Button {
                selectedTab = .settings
            } label: {
                Image(systemName: AppTab.settings.systemImage)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(
                        selectedTab == .settings
                            ? C5hColors.accent
                            : C5hColors.fgSecondary
                    )
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .frame(minWidth: 96, alignment: .trailing)
    }
}

private struct NavbarTabButton: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 13, weight: .medium))
                Text(tab.title)
                    .font(C5hTypography.tabFont)
            }
            .padding(.horizontal, C5hSpacing.md)
            .padding(.vertical, 6)
            .foregroundStyle(
                isSelected ? C5hColors.accent : C5hColors.fgSecondary
            )
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? C5hColors.accentMuted : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var tab: AppTab = .today
    return NavbarView(selectedTab: $tab)
        .frame(width: 1100)
}
