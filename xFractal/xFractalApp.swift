import SwiftUI
#if os(macOS)
import Sparkle

final class UpdaterHost {
    static let shared = UpdaterHost()
    let controller: SPUStandardUpdaterController
    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }
}
#endif

@main
struct xFractalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    UpdaterHost.shared.controller.checkForUpdates(nil)
                }
            }
        }
        #endif
    }
}
