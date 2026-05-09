import SwiftUI
import C5hCore

struct CommandRunTable: View {
    let runs: [CommandRun]
    @Binding var selection: CommandRun.ID?

    var body: some View {
        Table(runs, selection: $selection) {
            TableColumn("Started") { run in
                Text(run.startedAt.formatted(date: .abbreviated, time: .standard))
                    .font(C5hTypography.monoFont)
                    .lineLimit(1)
            }
            .width(min: 140, ideal: 160)

            TableColumn("Provider") { run in
                providerLabel(run.providerID)
            }
            .width(min: 110, ideal: 120)

            TableColumn("Type") { run in
                Text(run.runType.rawValue)
                    .font(C5hTypography.captionFont)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 120)

            TableColumn("Status") { run in
                StatusBadge(status: run.status)
            }
            .width(min: 90, ideal: 100)

            TableColumn("Duration") { run in
                Text(durationText(run))
                    .font(C5hTypography.captionFont)
                    .lineLimit(1)
            }
            .width(min: 70, ideal: 80)

            TableColumn("Exit") { run in
                if let code = run.exitCode {
                    Text("\(code)")
                        .font(C5hTypography.captionFont)
                        .foregroundStyle(code == 0 ? C5hColors.fgSecondary : .red)
                } else {
                    Text("—").font(C5hTypography.captionFont).foregroundStyle(C5hColors.fgTertiary)
                }
            }
            .width(min: 50, ideal: 60)

            TableColumn("CWD / Command") { run in
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.command)
                        .font(C5hTypography.captionFont)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let cwd = run.workingDirectory {
                        Text(cwd)
                            .font(C5hTypography.captionFont)
                            .foregroundStyle(C5hColors.fgTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .width(min: 200, ideal: 320)
        }
    }

    private func providerLabel(_ id: ProviderID) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(id == .claude ? ProviderBrandColor.claude : ProviderBrandColor.codex)
                .frame(width: 8, height: 8)
            Text(id.displayName).font(C5hTypography.captionFont).lineLimit(1)
        }
    }

    private func durationText(_ run: CommandRun) -> String {
        guard let s = run.durationSeconds else { return "—" }
        if s < 60 { return String(format: "%.1fs", s) }
        return String(format: "%dm%02ds", Int(s) / 60, Int(s) % 60)
    }
}

struct StatusBadge: View {
    let status: CommandRunStatus

    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color)
            )
    }

    private var color: Color {
        switch status {
        case .pending: .gray
        case .running: .blue
        case .succeeded: .green
        case .failed: .red
        case .timedOut: .orange
        case .cancelled: Color(nsColor: .tertiaryLabelColor)
        }
    }
}
