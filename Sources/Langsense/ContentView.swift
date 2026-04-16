import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Langsense")
                .font(.headline)

            permissionSection
            Divider()
            modeSection
            Divider()
            tokenSection
            Divider()
            actionSection
            Divider()
            Text("Hotkey: Control + Option + Command + Return")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 430)
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(appState.hasInputMonitoringPermission ? "Input Monitoring: available" : "Input Monitoring: grant in System Settings", systemImage: appState.hasInputMonitoringPermission ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(appState.hasInputMonitoringPermission ? .green : .orange)
            Label(appState.hasAccessibilityPermission ? "Accessibility: available" : "Accessibility: grant in System Settings", systemImage: appState.hasAccessibilityPermission ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(appState.hasAccessibilityPermission ? .green : .orange)

            Button("Refresh Permissions") {
                appState.refreshPermissions(prompt: true)
            }
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Correction mode")
                .font(.subheadline.weight(.semibold))

            Picker("Correction mode", selection: $appState.correctionMode) {
                ForEach(CorrectionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)

            Text("Current mode: \(appState.correctionMode.title)")
                .font(.caption.weight(.semibold))

            if appState.correctionMode == .manual {
                Label("Safest mode. Nothing changes unless you explicitly trigger conversion.", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label("Experimental auto mode. Triggers are intentionally strict, but manual mode is still safest.", systemImage: "flask")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text(appState.correctionMode.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent token")
                .font(.subheadline.weight(.semibold))
            Text(appState.recentToken.isEmpty ? "—" : appState.recentToken)
                .textSelection(.enabled)
                .font(.system(.body, design: .monospaced))

            Text("Suggestion")
                .font(.subheadline.weight(.semibold))

            if let suggestion = appState.suggestion {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(suggestion.original) → \(suggestion.replacement)")
                        .font(.system(.body, design: .monospaced))
                    Text("Target input: \(suggestion.targetLanguage.rawValue)")
                        .foregroundStyle(.secondary)
                    Text("Confidence: \(Int((suggestion.confidence * 100).rounded()))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(suggestion.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No likely mismatch detected yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Convert Last Token") {
                appState.applySuggestion()
            }
            .keyboardShortcut(.return, modifiers: [.command, .control, .option])
            .disabled(appState.suggestion == nil)

            Text("Manual mode is recommended. Boundary and aggressive modes are experimental and now use much stricter heuristics plus short cooldowns to reduce repeated rewrites.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(appState.lastActionMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
