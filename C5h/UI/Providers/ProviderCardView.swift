import SwiftUI
import C5hCore

struct ProviderCardView: View {
    /// Hardcoded — bumped only when a new app release changes the window length.
    private static let windowLengthDisplay = "5 hours"

    let id: ProviderID
    let status: ProviderStatus?
    let configuredPath: String
    let wakePrompt: String
    let refreshIntervalSeconds: Int
    let checkWhenIdle: Bool
    let usageCheck: ProviderUsageCheck?
    let isStatusLoading: Bool
    let isUsageLoading: Bool
    let isPromptFiring: Bool
    let promptFireDetail: String?
    let onVersion: () -> Void
    let onAuthStatus: () -> Void
    let onUsage: () -> Void
    let onFirePrompt: () -> Void
    let onSetPath: (String) -> Void
    let onClearPath: () -> Void
    let onSetWakePrompt: (String) -> Void
    let onSetRefreshInterval: (Int) -> Void
    let onSetCheckWhenIdle: (Bool) -> Void

    @State private var pathDraft: String = ""
    @State private var wakePromptDraft: String = ""
    @FocusState private var wakePromptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: C5hSpacing.md) {
            header
            Divider()
            section("Status") {
                statusGrid
            }
            Divider()
            section("Settings") {
                settings
            }
            Divider()
            section("Commands") {
                commands
            }
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
                Text("CLI path")
                    .font(C5hTypography.captionFont)
                    .foregroundStyle(C5hColors.fgSecondary)
                HStack(spacing: C5hSpacing.sm) {
                    TextField("/usr/local/bin/\(id.rawValue)", text: $pathDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        onSetPath(pathDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .buttonStyle(.glass)
                    Button("Clear") {
                        pathDraft = ""
                        onClearPath()
                    }
                    .buttonStyle(.glass)
                }
            }
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
                .onSubmit { wakePromptFocused = false }
            }
            GridRow {
                Text("Window length")
                    .font(C5hTypography.captionFont)
                    .foregroundStyle(C5hColors.fgSecondary)
                Text(Self.windowLengthDisplay)
                    .font(C5hTypography.captionFont)
            }
            GridRow {
                Text("Refresh rate")
                    .font(C5hTypography.captionFont)
                    .foregroundStyle(C5hColors.fgSecondary)
                Picker("", selection: refreshIntervalBinding) {
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                    Text("30 minutes").tag(1800)
                    Text("1 hour").tag(3600)
                }
                .labelsHidden()
                .fixedSize()
            }
            GridRow {
                Text("Check when idle")
                    .font(C5hTypography.captionFont)
                    .foregroundStyle(C5hColors.fgSecondary)
                Toggle("", isOn: checkWhenIdleBinding)
                    .labelsHidden()
            }
            GridRow {
                Color.clear.frame(width: 0, height: 0)
                Text("When off, C5h only checks usage while this provider has an active or planned window.")
                    .font(C5hTypography.captionFont)
                    .foregroundStyle(C5hColors.fgTertiary)
            }
        }
    }

    private var refreshIntervalBinding: Binding<Int> {
        Binding(get: { refreshIntervalSeconds }, set: { onSetRefreshInterval($0) })
    }

    private var checkWhenIdleBinding: Binding<Bool> {
        Binding(get: { checkWhenIdle }, set: { onSetCheckWhenIdle($0) })
    }

    private var header: some View {
        HStack(spacing: C5hSpacing.md) {
            Circle().fill(brandColor).frame(width: 10, height: 10)
            Text(id.displayName).font(C5hTypography.titleFont)
            Spacer()
            ProviderStatusBadge(state: healthState)
            if isStatusLoading || isUsageLoading { ProgressView().controlSize(.small) }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: C5hSpacing.sm) {
            Text(title)
                .font(C5hTypography.captionFont)
                .foregroundStyle(C5hColors.fgSecondary)
            content()
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
                row("Latest error", err, valueColor: .red)
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

    private func row(_ label: String, _ value: String, valueColor: Color = C5hColors.foreground) -> some View {
        GridRow {
            Text(label).font(C5hTypography.captionFont).foregroundStyle(C5hColors.fgSecondary)
            Text(value)
                .font(C5hTypography.captionFont)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var commands: some View {
        VStack(alignment: .leading, spacing: C5hSpacing.sm) {
            commandRow(
                title: "Version",
                preview: VersionCommand.displayCommand(providerID: id),
                systemImage: "number",
                isRunning: isStatusLoading,
                isDisabled: isStatusLoading,
                action: onVersion
            )
            commandRow(
                title: "Auth status",
                preview: AuthStatusCommand.displayCommand(providerID: id),
                systemImage: "person.badge.key",
                isRunning: isStatusLoading,
                isDisabled: isStatusLoading,
                action: onAuthStatus
            )
            commandRow(
                title: "Usage",
                preview: UsageCommand.displayCommand(providerID: id),
                systemImage: "chart.line.uptrend.xyaxis",
                detail: usageDetail,
                isRunning: isUsageLoading,
                isDisabled: isUsageLoading,
                action: onUsage
            )
            commandRow(
                title: "Prompt template",
                preview: PromptCommand.displayCommand(providerID: id, prompt: promptPreview),
                systemImage: "text.bubble",
                detail: promptFireDetail,
                isRunning: isPromptFiring,
                isDisabled: isPromptFiring,
                action: onFirePrompt
            )
        }
    }

    private func commandRow(
        title: String,
        preview: String,
        systemImage: String,
        detail: String? = nil,
        isRunning: Bool = false,
        isDisabled: Bool = false,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: C5hSpacing.sm) {
            Label(title, systemImage: systemImage)
                .font(C5hTypography.captionFont)
                .frame(width: 120, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(preview)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .font(C5hTypography.captionFont)
                        .foregroundStyle(detail.contains("failed") ? .red : C5hColors.fgSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: C5hSpacing.sm)
            if isRunning {
                ProgressView().controlSize(.small)
            }
            if let action {
                Button(action: action) {
                    Label("Run", systemImage: "play.fill")
                }
                .labelStyle(.iconOnly)
                .help("Run \(title)")
                .buttonStyle(.glass)
                .disabled(isDisabled)
            }
        }
    }

    private var usageDetail: String? {
        guard let usageCheck else { return nil }
        if let err = usageCheck.errorMessage, !err.isEmpty {
            return "failed \(usageCheck.checkedAt.formatted(date: .omitted, time: .shortened)): \(err)"
        }

        var parts = ["checked \(usageCheck.checkedAt.formatted(date: .omitted, time: .shortened))"]
        if let pct = usageCheck.usedPercentage {
            parts.append("\(Int(pct.rounded()))% used")
        }
        if let end = usageCheck.windowEndsAt {
            parts.append("resets \(end.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: " · ")
    }

    private var promptPreview: String {
        let trimmed = wakePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppSettingsKeys.defaultWakePromptFallback : trimmed
    }

    private var brandColor: Color {
        C5hColors.tintForProvider(id)
    }

    private var healthState: ProviderHealthState {
        guard let status else { return .unknown }
        return ProviderHealthState(from: status)
    }
}
