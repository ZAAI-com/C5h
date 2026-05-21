import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppTab
    let onReload: () -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(AppTab.navSections) { section in
                Section(section.title) {
                    ForEach(section.tabs) { tab in
                        NavigationLink(value: tab) {
                            Label(tab.title, systemImage: tab.systemImage)
                        }
                    }
                }
            }
        }
        .navigationTitle("C5h")
        .navigationSplitViewColumnWidth(220)
        .toolbar {
            if let help = selection.navbarReloadHelp {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onReload) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(help)
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var tab: AppTab = .today
    return NavigationSplitView {
        SidebarView(selection: $tab) {}
    } detail: {
        Text("Detail").frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: 1100, height: 700)
}
