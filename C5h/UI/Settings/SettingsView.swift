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
        }
        .padding(C5hSpacing.md)
    }

    private func reloadHeartbeat() async {
        guard let repo = appEnv.helperHeartbeatRepository else { return }
        heartbeat = try? await repo.latest()
    }
}
