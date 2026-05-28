import SwiftUI
import C5hCore

struct CommandRunDetailView: View {
    let run: CommandRun?

    var body: some View {
        if let run {
            content(for: run)
        } else {
            VStack {
                Image(systemName: "terminal").font(.system(size: 36, weight: .light))
                    .foregroundStyle(C5hColors.fgTertiary)
                Text("Select a run to inspect")
                    .font(C5hTypography.bodyFont)
                    .foregroundStyle(C5hColors.fgSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func content(for run: CommandRun) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: C5hSpacing.lg) {
                summary(run)
                    .padding(C5hSpacing.lg)
                    .background(.regularMaterial, in: C5hShape.rect(C5hRadius.l))

                commandSection(run)
                    .padding(C5hSpacing.lg)
                    .background(.regularMaterial, in: C5hShape.rect(C5hRadius.l))

                OutputLogView(title: "stdout", path: run.stdoutPath)
                    .frame(minHeight: 220)
                OutputLogView(title: "stderr", path: run.stderrPath)
                    .frame(minHeight: 140)

                if let parsed = run.parsedEventsJSON, !parsed.isEmpty {
                    parsedEventsSection(parsed)
                        .padding(C5hSpacing.lg)
                        .background(.regularMaterial, in: C5hShape.rect(C5hRadius.l))
                }
            }
            .padding(C5hSpacing.lg)
        }
    }

    private func summary(_ run: CommandRun) -> some View {
        VStack(alignment: .leading, spacing: C5hSpacing.sm) {
            HStack(spacing: C5hSpacing.md) {
                Text(run.providerID.displayName).font(C5hTypography.titleFont)
                StatusBadge(status: run.status)
                Spacer()
            }
            HStack(spacing: C5hSpacing.lg) {
                labelled("Command name", run.commandName.rawValue)
                labelled("Started", run.startedAt.c5hLogTimestamp)
                if let ended = run.endedAt {
                    labelled("Ended", ended.c5hLogTimestamp)
                }
                if let code = run.exitCode {
                    labelled("Exit", "\(code)")
                }
                if let dur = run.durationSeconds {
                    labelled("Duration", String(format: "%.2fs", dur))
                }
                if let v = run.toolVersion {
                    labelled("Tool", v)
                }
            }
            if let cwd = run.workingDirectory {
                labelled("CWD", cwd)
            }
            if let err = run.errorMessage {
                Text(err)
                    .font(C5hTypography.captionFont)
                    .foregroundStyle(.red)
            }
        }
    }

    private func commandSection(_ run: CommandRun) -> some View {
        VStack(alignment: .leading, spacing: C5hSpacing.sm) {
            Text("Command").font(C5hTypography.captionFont).foregroundStyle(C5hColors.fgSecondary)
            Text(run.command)
                .font(C5hTypography.monoFont)
                .textSelection(.enabled)
            Text("Arguments").font(C5hTypography.captionFont).foregroundStyle(C5hColors.fgSecondary)
            Text(formattedArgs(run.argumentsJSON))
                .font(C5hTypography.monoFont)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func parsedEventsSection(_ json: String) -> some View {
        VStack(alignment: .leading, spacing: C5hSpacing.sm) {
            Text("Parsed Events").font(C5hTypography.captionFont).foregroundStyle(C5hColors.fgSecondary)
            Text(json)
                .font(C5hTypography.monoFont)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(C5hTypography.captionFont).foregroundStyle(C5hColors.fgSecondary)
            Text(value).font(C5hTypography.bodyFont)
        }
    }

    private func formattedArgs(_ json: String) -> String {
        guard
            let data = json.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(withJSONObject: parsed, options: [.prettyPrinted, .sortedKeys]),
            let str = String(data: pretty, encoding: .utf8)
        else {
            return json
        }
        return str
    }
}
