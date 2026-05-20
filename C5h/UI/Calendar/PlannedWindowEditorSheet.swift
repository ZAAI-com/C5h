import SwiftUI
import C5hCore
import C5hStore

struct PlannedWindowEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlannedWindowDraft
    @State private var conflictCount: Int = 0
    @State private var lastError: String?
    @State private var isSaving: Bool = false

    let allWindows: [PlannedWindow]
    let onSave: (PlannedWindowDraft) async throws -> Void
    let onDelete: ((UUID) async throws -> Void)?

    init(
        editing existing: PlannedWindow? = nil,
        defaultProviderID: ProviderID = .claude,
        defaultStart: Date = Date().nextHourBoundary(),
        allWindows: [PlannedWindow],
        onSave: @escaping (PlannedWindowDraft) async throws -> Void,
        onDelete: ((UUID) async throws -> Void)? = nil
    ) {
        if let existing {
            _draft = State(initialValue: PlannedWindowDraft(
                existingID: existing.id,
                providerID: existing.providerID,
                startAt: existing.startAt,
                durationSeconds: existing.durationSeconds,
                projectPath: existing.projectPath,
                promptTemplateID: existing.promptTemplateID,
                status: existing.status,
                schedulePrompt: false,
                promptBody: "",
                createdAt: existing.createdAt
            ))
        } else {
            _draft = State(initialValue: PlannedWindowDraft(
                providerID: defaultProviderID,
                startAt: defaultStart
            ))
        }
        self.allWindows = allWindows
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $draft.providerID) {
                        ForEach(ProviderID.allCases) { id in
                            Text(id.displayName).tag(id)
                        }
                    }
                    DatePicker("Start", selection: $draft.startAt)
                    Stepper(
                        "Duration: \(durationLabel)",
                        value: Binding(
                            get: { draft.durationSeconds / 1800 },
                            set: { draft.durationSeconds = $0 * 1800 }
                        ),
                        in: 1...24
                    )
                    Picker("Status", selection: $draft.status) {
                        ForEach(PlannedWindowStatus.allCases, id: \.self) { st in
                            Text(st.rawValue).tag(st)
                        }
                    }
                    TextField(
                        "Project path (optional)",
                        text: Binding(
                            get: { draft.projectPath ?? "" },
                            set: { draft.projectPath = $0.isEmpty ? nil : $0 }
                        )
                    )
                }

                Section {
                    Toggle("Schedule a prompt for this window", isOn: $draft.schedulePrompt)
                    if draft.schedulePrompt {
                        TextEditor(text: $draft.promptBody)
                            .frame(minHeight: 100)
                            .overlay(alignment: .topLeading) {
                                if draft.promptBody.isEmpty {
                                    Text("Prompt body…")
                                        .foregroundStyle(C5hColors.fgTertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                }

                if conflictCount > 0 {
                    Section {
                        Label(
                            "\(conflictCount) overlap\(conflictCount == 1 ? "" : "s") with existing \(draft.providerID.displayName) window\(conflictCount == 1 ? "" : "s")",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                        .font(C5hTypography.captionFont)
                    }
                }

                if let lastError {
                    Section {
                        Label(lastError, systemImage: "exclamationmark.octagon")
                            .foregroundStyle(.red)
                            .font(C5hTypography.captionFont)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(draft.existingID == nil ? "New planned window" : "Edit planned window")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                if let id = draft.existingID, onDelete != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) {
                            Task { await delete(id: id) }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.existingID == nil ? "Create" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 480, idealHeight: 560)
        .onChange(of: draft.providerID) { recomputeConflicts() }
        .onChange(of: draft.startAt) { recomputeConflicts() }
        .onChange(of: draft.durationSeconds) { recomputeConflicts() }
        .onAppear { recomputeConflicts() }
    }

    private var durationLabel: String {
        let hours = Double(draft.durationSeconds) / 3600
        if hours.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(hours))h"
        }
        return String(format: "%.1fh", hours)
    }

    private func recomputeConflicts() {
        let result = PlannedWindowValidator.validate(
            candidate: draft.toPlannedWindow(),
            against: allWindows
        )
        conflictCount = result.conflictingWindowIDs.count
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(draft)
            dismiss()
        } catch {
            lastError = String(describing: error)
        }
    }

    private func delete(id: UUID) async {
        guard let onDelete else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await onDelete(id)
            dismiss()
        } catch {
            lastError = String(describing: error)
        }
    }
}

extension Date {
    func nextHourBoundary() -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: self)
        let base = cal.date(from: comps) ?? self
        return cal.date(byAdding: .hour, value: 1, to: base) ?? self
    }
}
