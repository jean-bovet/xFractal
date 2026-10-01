import SwiftUI
// SPARKLE is set only by the GitHub DMG target; the Mac App Store build updates through the store.
#if SPARKLE
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
        #if SPARKLE
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
