import SwiftUI
import C5hCore
import C5hStore

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var heartbeat: HelperHeartbeat?
    @State private var registration = HelperRegistrationService()
    #if DEBUG
    @State private var devRunner = HelperDevModeRunner()
    #endif

    var body: some View {
        Form {
            Section("Paths") {
                pathRow("Application Support", url: appEnv.paths?.appSupportDirectory) { url in
                    openFolder(url)
                }
                pathRow("Logs", url: appEnv.paths?.logsDirectory) { url in
                    openFolder(url)
                }
                pathRow("Command run logs", url: appEnv.paths?.commandRunsDirectory) { url in
                    openFolder(url)
                }
                pathRow("Database", url: appEnv.paths?.databaseURL, actionTitle: "Reveal in Finder") { url in
                    revealInFinder(url)
                }
            }
            Section("LaunchAgent") {
                LabeledContent("Status", value: registration.status.label)
                if case .error(let message) = registration.status {
                    Label(message, systemImage: "exclamationmark.octagon.fill")
                        .font(C5hTypography.captionFont)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button("Refresh status") { registration.refresh() }
                        .buttonStyle(.glass)
                    Button("Register") { registration.register() }
                        .buttonStyle(.glass)
                    Button("Unregister") { Task { await registration.unregister() } }
                        .buttonStyle(.glass)
                    Button("Open Login Items…") { openLoginItemsSettings() }
                        .buttonStyle(.glass)
                }
            }
            Section("Heartbeat") {
                LabeledContent("Last seen", value: heartbeat?.lastSeenAt.formatted(date: .omitted, time: .standard) ?? "—")
                LabeledContent("Helper version", value: heartbeat?.helperVersion ?? "—")
                LabeledContent("PID", value: heartbeat?.pid.map(String.init) ?? "—")
                Button("Refresh") { Task { await reloadHeartbeat() } }
                    .buttonStyle(.glass)
            }
            #if DEBUG
            Section("Debug subprocess runner") {
                LabeledContent("Running", value: devRunner.isRunning ? "yes" : "no")
                if let err = devRunner.lastError {
                    Text(err).font(C5hTypography.captionFont).foregroundStyle(.red)
                }
                HStack {
                    Button("Start") { devRunner.start() }
                        .buttonStyle(.glass)
                    Button("Stop") { devRunner.stop() }
                        .buttonStyle(.glass)
                }
                Text("Build the helper first: swift build --package-path Packages/C5hHelper")
                    .font(C5hTypography.captionFont)
                    .foregroundStyle(C5hColors.fgTertiary)
            }
            #endif
            Section("Time zone") {
                LabeledContent("Identifier", value: TimeZone.current.identifier)
                LabeledContent("Abbreviation", value: TimeZone.current.abbreviation() ?? "—")
                LabeledContent("Offset", value: timeZoneOffsetLabel)
                Text("Read-only — follows your system time zone. New windows are tagged with this zone at creation.")
                    .font(C5hTypography.captionFont)
                    .foregroundStyle(C5hColors.fgTertiary)
            }
            Section("Bundle") {
                LabeledContent("Bundle id", value: Bundle.main.bundleIdentifier ?? "—")
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
            }
            Section("Logs maintenance") {
                Button("Sweep logs older than 30 days") {
                    Task { await sweepLogs(policy: .thirtyDays) }
                }
                .buttonStyle(.glass)
                Button("Sweep logs older than 7 days") {
                    Task { await sweepLogs(policy: .sevenDays) }
                }
                .buttonStyle(.glass)
                if let result = lastSweepResult {
                    Text("Removed \(result.removedFileCount) files (\(result.freedBytes) bytes)")
                        .font(C5hTypography.captionFont)
                        .foregroundStyle(C5hColors.fgSecondary)
                }
            }
            Section("Diagnostics") {
                Button("Export debug bundle…") {
                    Task { await exportDebugBundle() }
                }
                .buttonStyle(.glass)
                if let path = lastExportedBundlePath, !path.isEmpty {
                    Text("Saved to \(path)")
                        .font(C5hTypography.captionFont)
                        .foregroundStyle(C5hColors.fgSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let err = lastExportError, !err.isEmpty {
                    Text("Export failed: \(err)")
                        .font(C5hTypography.captionFont)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Settings")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, C5hSpacing.sm)
            }
        }
        .task {
            await reloadHeartbeat()
        }
    }

    @State private var lastSweepResult: LogRetentionResult?
    @State private var lastExportedBundlePath: String?
    @State private var lastExportError: String?

    private func pathRow(
        _ title: String,
        url: URL?,
        actionTitle: String = "Open in Finder",
        action: @escaping (URL) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: C5hSpacing.xs) {
            HStack(spacing: C5hSpacing.sm) {
                Text(title)
                Spacer(minLength: C5hSpacing.sm)
                Button(actionTitle) {
                    if let url {
                        action(url)
                    }
                }
                .buttonStyle(.glass)
                .disabled(url == nil)
            }
            Text(url?.path ?? "—")
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private var timeZoneOffsetLabel: String {
        let seconds = TimeZone.current.secondsFromGMT()
        let sign = seconds >= 0 ? "+" : "-"
        let abs = Swift.abs(seconds)
        let h = abs / 3600
        let m = (abs % 3600) / 60
        return String(format: "GMT%@%02d:%02d", sign, h, m)
    }

    private func openFolder(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func sweepLogs(policy: LogRetentionPolicy) async {
        guard let dir = appEnv.paths?.commandRunsDirectory else { return }
        do {
            let result = try LogRetentionSweeper.sweep(directory: dir, policy: policy)
            lastSweepResult = result
        } catch {
            lastSweepResult = nil
        }
    }

    private func exportDebugBundle() async {
        guard let paths = appEnv.paths else { return }
        let exporter = DebugBundleExporter(appPaths: paths)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5h-debug-\(Int(Date().timeIntervalSince1970)).zip")
        do {
            try await exporter.export(to: dest)
            lastExportedBundlePath = dest.path
            lastExportError = nil
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            lastExportedBundlePath = nil
            lastExportError = error.localizedDescription
        }
    }

    private func reloadHeartbeat() async {
        guard let repo = appEnv.helperHeartbeatRepository else { return }
        heartbeat = try? await repo.latest()
    }

}
