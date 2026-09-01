import SwiftUI
import C5hCore

enum CalendarSelection: Hashable, Identifiable {
    case planned(PlannedWindow)
    case actual(ActualWindow5h)
    case weekly(ActualWindow7d)

    var id: String {
        switch self {
        case .planned(let w): "planned-\(w.id.uuidString)"
        case .actual(let w): "actual-\(w.id.uuidString)"
        case .weekly(let w): "weekly-\(w.id.uuidString)"
        }
    }
}

struct WindowInspectorView: View {
    let selection: CalendarSelection
    let resetEvent: UsageResetEvent?
    let onDelete: ((UUID) -> Void)?

    init(
        selection: CalendarSelection,
        resetEvent: UsageResetEvent? = nil,
        onDelete: ((UUID) -> Void)? = nil
    ) {
        self.selection = selection
        self.resetEvent = resetEvent
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
                case .weekly(let window):
                    weeklyContent(window)
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
        labelled("Start", format(window.startAt))
        labelled("End", format(window.endAt))
        labelled("Status", window.status.rawValue)
        if let project = window.projectPath {
            labelled("Project", project)
        }
    }

    @ViewBuilder
    private func weeklyContent(_ window: ActualWindow7d) -> some View {
        Text("Weekly window").font(C5hTypography.titleFont)
        labelled("Provider", window.providerID.displayName)
        labelled("Start", format(window.startAt))
        labelled("Reset", format(window.endAt))
        labelled("Remaining", BlockFormatters.formatPercent(window.remainingPercentage))
        labelled("Source", window.source.rawValue)
        labelled("Confidence", window.confidence.rawValue)
    }

    @ViewBuilder
    private func actualContent(_ window: ActualWindow5h) -> some View {
        Text("Actual window").font(C5hTypography.titleFont)
        labelled("Provider", window.providerID.displayName)
        labelled("Start", format(window.startAt))
        labelled("End", format(window.endAt))
        labelled("Source", window.source.rawValue)
        labelled("Confidence", window.confidence.rawValue)
        if let runID = window.commandRunID {
            labelled("Command run", runID.uuidString)
        }
        if let resetEvent {
            labelled("Reset detected", format(resetEvent.detectedAt))
            labelled("Old reset end", format(resetEvent.previousResetEnd))
            labelled("New reset end", format(resetEvent.newResetEnd))
        }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(C5hTypography.captionFont).foregroundStyle(C5hColors.fgSecondary)
            Text(value).font(C5hTypography.bodyFont).textSelection(.enabled)
        }
    }

    private func format(_ date: Date) -> String {
        date.c5hDateTime
    }
}

struct CalendarInspectorPane: View {
    let selection: CalendarSelection?
    var resetEvent: UsageResetEvent? = nil
    let onClose: () -> Void
    let onDelete: ((UUID) -> Void)?

    private let width: CGFloat = 360

    var body: some View {
        if let selection {
            HStack(spacing: 0) {
                Divider()
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.glass)
                        .help("Close inspector")
                    }
                    .padding(.horizontal, C5hSpacing.md)
                    .padding(.top, C5hSpacing.sm)
                    .padding(.bottom, C5hSpacing.xs)

                    WindowInspectorView(
                        selection: selection,
                        resetEvent: resetEvent,
                        onDelete: onDelete
                    )
                }
                .background(.thinMaterial)
            }
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .zIndex(10)
        }
    }
}
