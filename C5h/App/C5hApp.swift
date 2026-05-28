import SwiftUI

@main
struct C5hApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup("") {
            MainWindowView()
                .environment(environment)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands { AppCommands() }

        Settings {
            SettingsView()
                .environment(environment)
        }
    }
}
