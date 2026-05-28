import SwiftUI
import C5hCore

enum CalendarSelection: Hashable, Identifiable {
    case planned(PlannedWindow)
    case actual(ActualWindow5h)

    var id: String {
        switch self {
        case .planned(let w): "planned-\(w.id.uuidString)"
        case .actual(let w): "actual-\(w.id.uuidString)"
        }
    }
}

struct WindowInspectorView: View {
    let selection: CalendarSelection
    let onDelete: ((UUID) -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(
        selection: CalendarSelection,
        onDelete: ((UUID) -> Void)? = nil
    ) {
        self.selection = selection
        self.onDelete = onDelete
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: C5hSpacing.md) {
                switch selection {
                case .planned(let window):
                    plannedContent(window)
                    actions(for: window)
                case .actual(let window):
                    actualContent(window)
                }
            }
            .padding(C5hSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func actions(for window: PlannedWindow) -> some View {
        if let onDelete {
            HStack {
                Button(role: .destructive) { onDelete(window.id) } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.glass)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func plannedContent(_ window: PlannedWindow) -> some View {
        Text("Planned window").font(C5hTypography.titleFont)
        labelled("Provider", window.providerID.displayName)
        labelled("When", "\(format(window.startAt)) → \(format(window.endAt))")
        labelled("Status", window.status.rawValue)
        if let project = window.projectPath {
            labelled("Project", project)
        }
    }

    @ViewBuilder
    private func actualContent(_ window: ActualWindow5h) -> some View {
        Text("Actual window").font(C5hTypography.titleFont)
        labelled("Provider", window.providerID.displayName)
        labelled("When", "\(format(window.startAt)) → \(format(window.endAt))")
        labelled("Source", window.source.rawValue)
        labelled("Confidence", window.confidence.rawValue)
        if let runID = window.commandRunID {
            labelled("Command run", runID.uuidString)
        }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(C5hTypography.captionFont).foregroundStyle(C5hColors.fgSecondary)
            Text(value).font(C5hTypography.bodyFont).textSelection(.enabled)
        }
    }

    private func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }
}
