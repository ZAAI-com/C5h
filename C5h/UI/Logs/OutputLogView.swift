import SwiftUI
import Foundation

struct OutputLogView: View {
    let title: String
    let path: String?

    @State private var content: String = ""
    @State private var isLoading: Bool = false
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(C5hTypography.captionFont).foregroundStyle(C5hColors.fgSecondary)
                Spacer()
                if let path {
                    Text(path)
                        .font(C5hTypography.captionFont)
                        .foregroundStyle(C5hColors.fgTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        copyPath(path)
                    } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Copy path")
                }
            }
            .padding(.horizontal, C5hSpacing.md)
            .padding(.vertical, 6)
            .background(C5hColors.chrome)

            Divider()

            ScrollView {
                if isLoading {
                    ProgressView().padding()
                } else if let loadError {
                    Text(loadError).foregroundStyle(.red).padding()
                } else if content.isEmpty {
                    Text("No output.")
                        .font(C5hTypography.captionFont)
                        .foregroundStyle(C5hColors.fgTertiary)
                        .padding()
                } else {
                    Text(content)
                        .font(C5hTypography.monoFont)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(C5hSpacing.md)
                        .textSelection(.enabled)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: path) {
            await loadContent()
        }
    }

    private func loadContent() async {
        guard let path else {
            content = ""
            loadError = nil
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        let url = URL(fileURLWithPath: path)
        do {
            let data = try Data(contentsOf: url)
            let truncated: Data
            let limit = 1_048_576 // 1 MB
            if data.count > limit {
                truncated = data.suffix(limit)
                content = "[…truncated to last 1 MB…]\n" + (String(data: truncated, encoding: .utf8) ?? "")
            } else {
                content = String(data: data, encoding: .utf8) ?? "[binary content]"
            }
        } catch {
            content = ""
            loadError = "Could not load: \(error.localizedDescription)"
        }
    }

    private func copyPath(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }
}
