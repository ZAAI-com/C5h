import SwiftUI
import C5hCore

struct ProviderCardView: View {
    /// Hardcoded — bumped only when a new app release changes the window length.
    private static let windowLengthDisplay = "5 hours"

    let id: ProviderID
    let status: ProviderStatus?
    let configuredPath: String
    let wakePrompt: String
    let isLoading: Bool
    let onVersion: () -> Void
    let onAuthStatus: () -> Void
    let onSetPath: (String) -> Void
    let onClearPath: () -> Void
    let onSetWakePrompt: (String) -> Void

    @State private var pathDraft: String = ""
    @State private var wakePromptDraft: String = ""
    @FocusState private var wakePromptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: C5hSpacing.md) {
            header
            Divider()
            statusGrid
            Divider()
            settings
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
        .onAppear {
            pathDraft = configuredPath
            wakePromptDraft = wakePrompt
        }
        .onChange(of: configuredPath) { _, newValue in pathDraft = newValue }
        .onChange(of: wakePrompt) { _, newValue in
            if !wakePromptFocused { wakePromptDraft = newValue }
        }
        .onChange(of: wakePromptFocused) { _, isFocused in
            if !isFocused, wakePromptDraft != wakePrompt {
                onSetWakePrompt(wakePromptDraft)
            }
        }
    }

    private var settings: some View {
        Grid(alignment: .leading, horizontalSpacing: C5hSpacing.lg, verticalSpacing: 6) {
            GridRow {
                Text("Wake prompt")
                    .font(C5hTypography.captionFont)
                    .foregroundStyle(C5hColors.fgSecondary)
                TextField(
                    AppSettingsKeys.defaultWakePromptFallback,
                    text: $wakePromptDraft,
                    prompt: Text(AppSettingsKeys.defaultWakePromptFallback)
                )
                .textFieldStyle(.roundedBorder)
                .focused($wakePromptFocused)
                .onSubmit { onSetWakePrompt(wakePromptDraft) }
            }
            GridRow {
                Text("Window length")
                    .font(C5hTypography.captionFont)
                    .foregroundStyle(C5hColors.fgSecondary)
                Text(Self.windowLengthDisplay)
                    .font(C5hTypography.captionFont)
            }
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
