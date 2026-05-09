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
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            helperTab.tabItem { Label("Helper", systemImage: "bolt.horizontal.circle") }
            advancedTab.tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 620, height: 460)
        .padding(C5hSpacing.lg)
        .task { await reloadHeartbeat() }
    }

    private var generalTab: some View {
        Form {
            LabeledContent("Database location", value: appEnv.paths?.databaseURL.path ?? "—")
                .lineLimit(1)
                .truncationMode(.middle)
            LabeledContent("Logs directory", value: appEnv.paths?.logsDirectory.path ?? "—")
                .lineLimit(1)
                .truncationMode(.middle)
            LabeledContent("Default window length", value: "5 hours")
        }
        .padding(C5hSpacing.md)
    }

    private var helperTab: some View {
        Form {
            Section("LaunchAgent") {
                LabeledContent("Status", value: registration.status.label)
                HStack {
                    Button("Refresh status") { registration.refresh() }
                    Button("Register") { Task { await registration.register() } }
                    Button("Unregister") { Task { await registration.unregister() } }
                }
            }
            Section("Heartbeat") {
                LabeledContent("Last seen", value: heartbeat?.lastSeenAt.formatted(date: .omitted, time: .standard) ?? "—")
                LabeledContent("Helper version", value: heartbeat?.helperVersion ?? "—")
                LabeledContent("PID", value: heartbeat?.pid.map(String.init) ?? "—")
                Button("Refresh") { Task { await reloadHeartbeat() } }
            }
            #if DEBUG
            Section("Debug subprocess runner") {
                LabeledContent("Running", value: devRunner.isRunning ? "yes" : "no")
                if let err = devRunner.lastError {
                    Text(err).font(C5hTypography.captionFont).foregroundStyle(.red)
                }
                HStack {
                    Button("Start") { devRunner.start() }
                    Button("Stop") { devRunner.stop() }
                }
                Text("Build the helper first: swift build --package-path Packages/C5hHelper")
                    .font(C5hTypography.captionFont)
                    .foregroundStyle(C5hColors.fgTertiary)
            }
            #endif
        }
        .padding(C5hSpacing.md)
    }

    private var advancedTab: some View {
        Form {
            Section("Database") {
                LabeledContent("Path", value: appEnv.paths?.databaseURL.path ?? "—")
                    .lineLimit(1).truncationMode(.middle)
                Button("Reveal in Finder") {
                    if let url = appEnv.paths?.databaseURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
            Section("Bundle") {
                LabeledContent("Bundle id", value: Bundle.main.bundleIdentifier ?? "—")
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
            }
            Section("Logs maintenance") {
                Button("Sweep logs older than 30 days") {
                    Task { await sweepLogs(policy: .thirtyDays) }
                }
                Button("Sweep logs older than 7 days") {
                    Task { await sweepLogs(policy: .sevenDays) }
                }
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
                if let path = lastExportedBundlePath {
                    Text("Saved to \(path)")
                        .font(C5hTypography.captionFont)
                        .foregroundStyle(C5hColors.fgSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(C5hSpacing.md)
    }

    @State private var lastSweepResult: LogRetentionResult?
    @State private var lastExportedBundlePath: String?

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
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            lastExportedBundlePath = "Export failed: \(error.localizedDescription)"
        }
    }

    private func reloadHeartbeat() async {
        guard let repo = appEnv.helperHeartbeatRepository else { return }
        heartbeat = try? await repo.latest()
    }
}
