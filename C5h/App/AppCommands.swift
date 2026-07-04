import SwiftUI

struct AppCommands: Commands {
    let updaterService: UpdaterService

    var body: some Commands {
        CommandGroup(replacing: .newItem) { }
        CommandGroup(after: .appInfo) {
            if updaterService.isEnabled {
                CheckForUpdatesButton(updaterService: updaterService)
            }
        }
    }
}

/// A dedicated view so @Observable tracking re-evaluates the menu item when
/// canCheckForUpdates flips around an update session.
private struct CheckForUpdatesButton: View {
    let updaterService: UpdaterService

    var body: some View {
        Button("Check for Updates…") { updaterService.checkForUpdates() }
            .disabled(!updaterService.canCheckForUpdates)
    }
}
