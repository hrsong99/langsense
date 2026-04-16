import SwiftUI

@main
struct WrongLanguageHelperApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("WrongLanguageHelper", systemImage: appState.suggestion == nil ? "keyboard" : "exclamationmark.bubble") {
            ContentView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}
