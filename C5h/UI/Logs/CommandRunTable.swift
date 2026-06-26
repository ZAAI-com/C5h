import SwiftUI
import C5hCore

struct CommandRunTable: View {
    let runs: [CommandRun]
    @Binding var selection: CommandRun.ID?

    var body: some View {
        Table(runs, selection: $selection) {
            TableColumn("Started") { run in
                Text(run.startedAt.c5hDateTime)
                    .font(C5hTypography.monoFont)
                    .lineLimit(1)
            }
            .width(min: 180, ideal: 195)

            TableColumn("Provider") { run in
                providerLabel(run.providerID)
            }
            .width(min: 70, ideal: 80)

            TableColumn("Command") { run in
                Text(run.commandName.rawValue)
                    .font(C5hTypography.captionFont)
                    .lineLimit(1)
            }
            .width(min: 115, ideal: 135)

            TableColumn("Status") { run in
                StatusBadge(status: run.status)
            }
            .width(min: 85, ideal: 95)

            TableColumn("Duration") { run in
                Text(durationText(run))
                    .font(C5hTypography.captionFont)
                    .lineLimit(1)
            }
            .width(min: 75, ideal: 85)
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
