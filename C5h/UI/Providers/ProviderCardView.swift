import SwiftUI
import C5hCore

struct ProviderCardView: View {
    let id: ProviderID
    let status: ProviderStatus?
    let configuredPath: String
    let isLoading: Bool
    let onDetect: () -> Void
    let onTest: () -> Void
    let onChoosePath: () -> Void
    let onClearPath: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: C5hSpacing.md) {
            header
            Divider()
            statusGrid
            Divider()
            actions
        }
        .padding(C5hSpacing.lg)
        .background(C5hColors.chrome)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(brandColor.opacity(0.25), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: C5hSpacing.md) {
            Circle().fill(brandColor).frame(width: 10, height: 10)
            Text(id.displayName).font(C5hTypography.titleFont)
            Spacer()
            ProviderStatusBadge(state: healthState)
            if isLoading { ProgressView().scaleEffect(0.6) }
        }
    }

    private var statusGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: C5hSpacing.lg, verticalSpacing: 6) {
            row("Installed", installedText)
            row("CLI path", cliPathText)
            row("Version", status?.version ?? "—")
            row("Auth", authText)
            row("Last checked", status?.lastCheckedAt.formatted(date: .omitted, time: .standard) ?? "—")
            if let err = status?.errorMessage, !err.isEmpty {
                GridRow {
                    Text("Error").font(C5hTypography.captionFont).foregroundStyle(C5hColors.fgSecondary)
                    Text(err).font(C5hTypography.captionFont).foregroundStyle(.red)
                }
            }
        }
    }

    private var installedText: String {
        guard let installed = status?.isInstalled else { return "unknown" }
        return installed ? "yes" : "no"
    }

    private var authText: String {
        guard let auth = status?.isAuthenticated else { return "unknown" }
        return auth ? "yes" : "no"
    }

    private var cliPathText: String {
        if let path = status?.cliPath, !path.isEmpty { return path }
        if !configuredPath.isEmpty { return configuredPath }
        return "—"
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).font(C5hTypography.captionFont).foregroundStyle(C5hColors.fgSecondary)
            Text(value).font(C5hTypography.captionFont).lineLimit(1).truncationMode(.middle)
        }
    }

    private var actions: some View {
        HStack(spacing: C5hSpacing.sm) {
            Button("Detect CLI", action: onDetect).disabled(isLoading)
            Button("Run test command", action: onTest).disabled(isLoading)
            Spacer()
            Menu("CLI path…") {
                Button("Choose…", action: onChoosePath)
                if !configuredPath.isEmpty {
                    Button("Clear override", action: onClearPath)
                }
            }
            .frame(maxWidth: 160)
        }
    }

    private var brandColor: Color {
        id == .claude ? ProviderBrandColor.claude : ProviderBrandColor.codex
    }

    private var healthState: ProviderHealthState {
        guard let status else { return .unknown }
        return ProviderHealthState(from: status)
    }
}
