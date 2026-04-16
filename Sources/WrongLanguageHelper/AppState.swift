import AppKit
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var recentToken: String = ""
    @Published var suggestion: ConversionSuggestion?
    @Published var lastActionMessage: String = "Ready"
    @Published var hasAccessibilityPermission: Bool = false
    @Published var hasInputMonitoringPermission: Bool = false
    @Published var correctionMode: CorrectionMode = .manual {
        didSet {
            UserDefaults.standard.set(correctionMode.rawValue, forKey: Self.correctionModeDefaultsKey)
        }
    }

    private static let correctionModeDefaultsKey = "CorrectionMode"
    private static let correctedTokenCooldown: TimeInterval = 2.0
    private static let correctedTokenCacheLimit = 24

    private let typingMonitor = TypingMonitor()
    private let inputSourceController = InputSourceController()
    private let textReplacer = TextReplacementService()
    private var hotKeyController: HotKeyController?
    private var cancellables = Set<AnyCancellable>()
    private var pendingBoundarySuffix = ""
    private var correctedTokens: [String: Date] = [:]

    init() {
        if let storedMode = UserDefaults.standard.string(forKey: Self.correctionModeDefaultsKey),
           let correctionMode = CorrectionMode(rawValue: storedMode) {
            self.correctionMode = correctionMode
        } else {
            self.correctionMode = .manual
        }

        refreshPermissions(prompt: true)
        setupBindings()
        typingMonitor.start()
        registerHotKey()
    }

    deinit {
        hotKeyController?.unregister()
        typingMonitor.stop()
    }

    func refreshPermissions(prompt: Bool = false) {
        hasAccessibilityPermission = PermissionController.checkAccessibility(prompt: prompt)
        hasInputMonitoringPermission = PermissionController.checkInputMonitoring()
    }

    func applySuggestion() {
        guard let suggestion else {
            lastActionMessage = "No suggestion available."
            return
        }

        _ = performCorrection(
            suggestion: suggestion,
            deleteCount: suggestion.deleteCount + pendingBoundarySuffix.count,
            replacement: suggestion.replacement + pendingBoundarySuffix,
            resultingToken: "",
            messagePrefix: "Replaced",
            consumeExpectedToken: suggestion.original
        )
    }

    private func setupBindings() {
        typingMonitor.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.pruneCorrectionCooldowns()

                self.recentToken = snapshot.token
                self.suggestion = self.manualSuggestion(for: snapshot.token)
                self.pendingBoundarySuffix = snapshot.justReachedBoundary ? snapshot.boundarySuffix : ""

                if snapshot.justReachedBoundary {
                    self.handleBoundary(snapshot: snapshot)
                } else {
                    self.handleLiveToken(snapshot.token)
                }
            }
            .store(in: &cancellables)
    }

    private func handleBoundary(snapshot: TypingSnapshot) {
        guard correctionMode == .boundaryAutoFix,
              !shouldSuppressAutoCorrection(for: snapshot.token) else {
            return
        }

        guard let boundarySuggestion = ConversionEngine.suggest(for: snapshot.token, profile: .boundaryAutoFix) else {
            return
        }

        let deleteCount = boundarySuggestion.deleteCount + snapshot.boundarySuffix.count
        let replacement = boundarySuggestion.replacement + snapshot.boundarySuffix
        _ = performCorrection(
            suggestion: boundarySuggestion,
            deleteCount: deleteCount,
            replacement: replacement,
            resultingToken: "",
            messagePrefix: "Auto-fixed",
            consumeExpectedToken: nil
        )
    }

    private func handleLiveToken(_ token: String) {
        guard correctionMode == .aggressive,
              !shouldSuppressAutoCorrection(for: token) else {
            return
        }

        guard let aggressiveSuggestion = ConversionEngine.suggest(for: token, profile: .aggressive) else {
            return
        }

        let resultingToken = aggressiveSuggestion.replacement
        _ = performCorrection(
            suggestion: aggressiveSuggestion,
            deleteCount: aggressiveSuggestion.deleteCount,
            replacement: resultingToken,
            resultingToken: resultingToken,
            messagePrefix: "Aggressively auto-fixed",
            consumeExpectedToken: nil
        )
    }

    @discardableResult
    private func performCorrection(
        suggestion: ConversionSuggestion,
        deleteCount: Int,
        replacement: String,
        resultingToken: String,
        messagePrefix: String,
        consumeExpectedToken: String?
    ) -> Bool {
        refreshPermissions(prompt: correctionMode == .manual)

        guard hasAccessibilityPermission else {
            lastActionMessage = "Accessibility permission is required to replace text."
            return false
        }

        let previousInputSource = inputSourceController.currentInputSourceID()
        let sourceChanged = inputSourceController.selectInputSource(for: suggestion.targetLanguage)
        guard sourceChanged else {
            lastActionMessage = "Could not switch to \(suggestion.targetLanguage.rawValue) input source."
            return false
        }

        let replacementResult = textReplacer.replaceRecentText(deleteCount: deleteCount, replacement: replacement)
        guard replacementResult else {
            if let previousInputSource,
               previousInputSource != inputSourceController.currentInputSourceID() {
                _ = inputSourceController.selectInputSource(id: previousInputSource)
            }
            lastActionMessage = "Could not replace text in the focused app. Restored the previous input source when possible."
            return false
        }

        rememberCorrection(original: suggestion.original, replacement: suggestion.replacement)
        typingMonitor.prepareForProgrammaticReplacement(resultingToken: resultingToken)
        if let consumeExpectedToken {
            typingMonitor.consumeLastToken(expected: consumeExpectedToken)
        }

        self.pendingBoundarySuffix = ""
        let percent = Int((suggestion.confidence * 100).rounded())
        self.lastActionMessage = "\(messagePrefix) ‘\(suggestion.original)’ → ‘\(suggestion.replacement)’ (\(percent)% confidence)."
        self.recentToken = resultingToken
        self.suggestion = manualSuggestion(for: resultingToken)
        return true
    }

    private func manualSuggestion(for token: String) -> ConversionSuggestion? {
        guard !isInCorrectionCooldown(token) else { return nil }
        return ConversionEngine.suggest(for: token, profile: .manual)
    }

    private func shouldSuppressAutoCorrection(for token: String) -> Bool {
        token.isEmpty || isInCorrectionCooldown(token)
    }

    private func isInCorrectionCooldown(_ token: String) -> Bool {
        guard let timestamp = correctedTokens[normalizedToken(token)] else {
            return false
        }
        return Date().timeIntervalSince(timestamp) < Self.correctedTokenCooldown
    }

    private func rememberCorrection(original: String, replacement: String) {
        let now = Date()
        correctedTokens[normalizedToken(original)] = now
        correctedTokens[normalizedToken(replacement)] = now

        if correctedTokens.count > Self.correctedTokenCacheLimit {
            let sorted = correctedTokens.sorted { $0.value > $1.value }
            correctedTokens = Dictionary(uniqueKeysWithValues: sorted.prefix(Self.correctedTokenCacheLimit))
        }
    }

    private func pruneCorrectionCooldowns() {
        let now = Date()
        correctedTokens = correctedTokens.filter { now.timeIntervalSince($0.value) < Self.correctedTokenCooldown }
    }

    private func normalizedToken(_ token: String) -> String {
        token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func registerHotKey() {
        hotKeyController = HotKeyController(keyCode: UInt32(kVK_Return), modifiers: UInt32(controlKey + optionKey + cmdKey)) { [weak self] in
            Task { @MainActor in
                self?.applySuggestion()
            }
        }
        hotKeyController?.register()
    }
}
