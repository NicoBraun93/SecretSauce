import Combine
import Sparkle
import SwiftUI

/// Wraps Sparkle's standard updater so the rest of the app can drive it from
/// SwiftUI. Sparkle needs a real `.app` bundle with `SUFeedURL` + `SUPublicEDKey`
/// in its Info.plist (see package-app.sh). In dev mode (`swift run`) there is no
/// bundle and no feed URL, so we skip starting the updater entirely — the menu
/// item stays disabled instead of logging Sparkle errors on every launch.
final class UpdaterService: ObservableObject {
    /// Drives the enabled state of the "Check for Updates…" menu item.
    @Published var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController?

    init() {
        // Only wire up Sparkle when running as a packaged app that actually
        // carries a feed URL. Bundle-less dev builds get a no-op updater.
        let hasFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        if hasFeed {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            self.controller = controller
            controller.updater.publisher(for: \.canCheckForUpdates)
                .assign(to: &$canCheckForUpdates)
        } else {
            self.controller = nil
        }
    }

    /// Presents Sparkle's update UI (progress, release notes, install prompt).
    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }
}

/// Menu item that reflects Sparkle's readiness — disabled while an update check
/// is already in flight, or in bundle-less dev builds.
struct CheckForUpdatesView: View {
    @ObservedObject var updater: UpdaterService

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
