import SwiftUI
import UniformTypeIdentifiers
import C5hCore

struct StartProviderNowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var providerID: ProviderID
    @State private var prompt: String = "Begin a 5-hour focused coding session."
    @State private var projectPath: String = ""
    @State private var lastError: String?
    @State private var isStarting: Bool = false
    @State private var pickingFolder: Bool = false

    let onStart: (ProviderID, String, String?) async throws -> Void

    init(
        defaultProviderID: ProviderID = .claude,
        onStart: @escaping (ProviderID, String, String?) async throws -> Void
    ) {
        self._providerID = State(initialValue: defaultProviderID)
        self.onStart = onStart
    }

    var body: some View {
        VStack(alignment: .leading, spacing: C5hSpacing.lg) {
            Text("Start \(providerID.displayName) window now")
                .font(C5hTypography.titleFont)
            Form {
                Picker("Provider", selection: $providerID) {
                    ForEach(ProviderID.allCases) { id in
                        Text(id.displayName).tag(id)
                    }
                }
                HStack {
                    TextField("Project path (optional)", text: $projectPath)
                    Button("Choose…") { pickingFolder = true }
                }
                VStack(alignment: .leading) {
                    Text("Prompt")
                    TextEditor(text: $prompt).frame(minHeight: 120)
                }
            }
            if let lastError {
                Text(lastError).foregroundStyle(.red).font(C5hTypography.captionFont)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Start") { Task { await start() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isStarting || prompt.isEmpty)
            }
        }
        .padding(C5hSpacing.xl)
        .frame(width: 540)
        .fileImporter(
            isPresented: $pickingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    projectPath = url.path
                }
            case .failure: break
            }
        }
    }

    private func start() async {
        isStarting = true
        defer { isStarting = false }
        do {
            try await onStart(providerID, prompt, projectPath.isEmpty ? nil : projectPath)
            dismiss()
        } catch {
            lastError = String(describing: error)
        }
    }
}
