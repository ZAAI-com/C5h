import SwiftUI
import C5hCore

enum CalendarSelection: Hashable, Identifiable {
    case planned(PlannedWindow)
    case actual(ActualWindow)

    var id: String {
        switch self {
        case .planned(let w): "planned-\(w.id.uuidString)"
        case .actual(let w): "actual-\(w.id.uuidString)"
        }
    }
}

struct WindowInspectorView: View {
    let selection: CalendarSelection
    let onEdit: ((PlannedWindow) -> Void)?
    let onDelete: ((UUID) -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(
        selection: CalendarSelection,
        onEdit: ((PlannedWindow) -> Void)? = nil,
        onDelete: ((UUID) -> Void)? = nil
    ) {
        self.selection = selection
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: C5hSpacing.md) {
            switch selection {
            case .planned(let window):
                plannedContent(window)
                actions(for: window)
            case .actual(let window):
                actualContent(window)
                HStack {
                    Spacer()
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(width: 360)
        .padding(C5hSpacing.lg)
    }

    @ViewBuilder
    private func actions(for window: PlannedWindow) -> some View {
        HStack {
            if let onDelete {
                Button(role: .destructive) { onDelete(window.id) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            Spacer()
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            if let onEdit {
                Button("Edit…") { onEdit(window) }
                    .keyboardShortcut(.defaultAction)
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
    private func actualContent(_ window: ActualWindow) -> some View {
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
