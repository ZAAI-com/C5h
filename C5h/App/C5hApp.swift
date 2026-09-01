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
        // Passed explicitly: Commands are not part of the window's view
        // hierarchy, so the .environment(environment) on MainWindowView does
        // not reach them.
        .commands { AppCommands(updaterService: environment.updaterService) }

        Settings {
            SettingsView()
                .environment(environment)
        }
    }
}
