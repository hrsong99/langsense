import SwiftUI

struct LangsenseApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Langsense", systemImage: appState.suggestion == nil ? "keyboard" : "exclamationmark.bubble") {
            ContentView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}

@main
struct EntryPoint {
    static func main() {
        if CommandLine.arguments.contains("--regression-check") {
            // Touching NSApplication.shared forces AppKit to initialize so that
            // NSSpellChecker.shared is safe to use from this pre-main context.
            _ = NSApplication.shared
            exit(RegressionHarness.run() ? 0 : 1)
        }
        LangsenseApp.main()
    }
}
