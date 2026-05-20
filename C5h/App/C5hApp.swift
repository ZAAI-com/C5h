import SwiftUI

@main
struct C5hApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup("C5h") {
            MainWindowView()
                .environment(environment)
        }
        .windowResizability(.contentMinSize)
        .commands { AppCommands() }

        Settings {
            SettingsView()
                .environment(environment)
        }
    }
}
