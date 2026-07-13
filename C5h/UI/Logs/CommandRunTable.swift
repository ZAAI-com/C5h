import SwiftUI
import C5hCore
import C5hStore

struct CommandRunTable: View {
    let entries: [CommandRunEntry]
    @Binding var selection: CommandRunEntry.ID?

    var body: some View {
        Table(entries, selection: $selection) {
            TableColumn("Started") { entry in
                startedCell(entry)
            }
            .width(min: 180, ideal: 195)

            TableColumn("Provider") { entry in
                providerCell(entry)
            }
            .width(min: 70, ideal: 80)

            TableColumn("Command") { entry in
                commandCell(entry)
            }
            .width(min: 115, ideal: 135)

            TableColumn("Status") { entry in
                statusCell(entry)
            }
            .width(min: 85, ideal: 95)

            TableColumn("Duration") { entry in
                durationCell(entry)
            }
            .width(min: 75, ideal: 85)
        }
    }

    @ViewBuilder
    private func startedCell(_ entry: CommandRunEntry) -> some View {
        switch entry {
        case .readable(let run):
            Text(run.startedAt.c5hDateTime)
                .font(C5hTypography.monoFont)
                .lineLimit(1)
        case .unreadable(_, let startedAt):
            Text(startedAt?.c5hDateTime ?? "—")
                .font(C5hTypography.monoFont)
                .foregroundStyle(C5hColors.fgTertiary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func providerCell(_ entry: CommandRunEntry) -> some View {
        switch entry {
        case .readable(let run):
            providerLabel(run.providerID)
        case .unreadable:
            Text("—").font(C5hTypography.captionFont).foregroundStyle(C5hColors.fgTertiary)
        }
    }

    @ViewBuilder
    private func commandCell(_ entry: CommandRunEntry) -> some View {
        switch entry {
        case .readable(let run):
            Text(run.commandName.rawValue)
                .font(C5hTypography.captionFont)
                .lineLimit(1)
        case .unreadable:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text("Log not readable")
                    .font(C5hTypography.captionFont)
                    .lineLimit(1)
            }
            .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func statusCell(_ entry: CommandRunEntry) -> some View {
        switch entry {
        case .readable(let run):
            StatusBadge(status: run.status)
        case .unreadable:
            Text("—").font(C5hTypography.captionFont).foregroundStyle(C5hColors.fgTertiary)
        }
    }

    @ViewBuilder
    private func durationCell(_ entry: CommandRunEntry) -> some View {
        switch entry {
        case .readable(let run):
            Text(durationText(run))
                .font(C5hTypography.captionFont)
                .lineLimit(1)
        case .unreadable:
            Text("—").font(C5hTypography.captionFont).foregroundStyle(C5hColors.fgTertiary)
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
