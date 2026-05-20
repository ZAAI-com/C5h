import SwiftUI
import C5hCore

struct ProviderCardView: View {
    let id: ProviderID
    let status: ProviderStatus?
    let configuredPath: String
    let isLoading: Bool
    let onVersion: () -> Void
    let onAuthStatus: () -> Void
    let onSetPath: (String) -> Void
    let onClearPath: () -> Void

    @State private var pathDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: C5hSpacing.md) {
            header
            Divider()
            statusGrid
            Divider()
            actions
        }
        .padding(C5hSpacing.lg)
        // LEVEL 2 — Material content card with a thin brand-tinted stroke
        // for identity. Action buttons inside stay glass.
        .background(.regularMaterial, in: C5hShape.rect(C5hRadius.l))
        .overlay {
            C5hShape.rect(C5hRadius.l)
                .strokeBorder(brandColor.opacity(0.15), lineWidth: 1)
        }
        .onAppear { pathDraft = configuredPath }
        .onChange(of: configuredPath) { _, newValue in pathDraft = newValue }
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
            Button("Version", action: onVersion)
                .buttonStyle(.glass)
                .disabled(isLoading)
            Button("Auth status", action: onAuthStatus)
                .buttonStyle(.glass)
                .disabled(isLoading)
            Spacer()
            HStack(spacing: C5hSpacing.xs) {
                TextField("/usr/local/bin/\(id.executableName)", text: $pathDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Button("Save") { onSetPath(pathDraft) }
                    .buttonStyle(.glass)
                    .disabled(pathDraft == configuredPath)
                if !configuredPath.isEmpty {
                    Button("Clear", action: onClearPath)
                        .buttonStyle(.glass)
                }
            }
        }
    }

    private var brandColor: Color {
        C5hColors.tintForProvider(id)
    }

    private var healthState: ProviderHealthState {
        guard let status else { return .unknown }
        return ProviderHealthState(from: status)
    }
}
