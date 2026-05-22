import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppTab

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
        .navigationSplitViewColumnWidth(220)
    }
}

#Preview {
    @Previewable @State var tab: AppTab = .today
    return NavigationSplitView {
        SidebarView(selection: $tab)
    } detail: {
        Text("Detail").frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: 1100, height: 700)
}
