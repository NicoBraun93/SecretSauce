import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // When run as a bare SwiftPM executable (dev mode) there is no bundle,
        // so the process defaults to an accessory app without a Dock icon or focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct SecretSauceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 980, minHeight: 640)
                .tint(Color.dsPrimary)
            // No forced color scheme: the UI follows the system appearance
            // (dark when macOS is in dark mode, light otherwise).
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 740)
    }
}
