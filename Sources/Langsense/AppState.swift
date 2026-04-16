import AppKit
import Carbon.HIToolbox
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
    @Published var revertTrigger: RevertTrigger = .rightCommand {
        didSet {
            UserDefaults.standard.set(revertTrigger.rawValue, forKey: Self.revertTriggerDefaultsKey)
        }
    }

    private static let correctionModeDefaultsKey = "CorrectionMode"
    private static let revertTriggerDefaultsKey = "RevertTrigger"
    private static let correctedTokenCooldown: TimeInterval = 2.0
    private static let correctedTokenCacheLimit = 24
    private static let revertWindow: TimeInterval = 1.5

    private let typingMonitor = TypingMonitor()
    private let inputSourceController = InputSourceController()
    private let textReplacer = TextReplacementService()
    private let blocklist = Blocklist()
    private var applyHotKey: HotKeyController?
    private var cancellables = Set<AnyCancellable>()
    private var pendingBoundarySuffix = ""
    private var correctedTokens: [String: Date] = [:]
    private var lastCorrection: LastCorrection?

    private struct LastCorrection {
        let original: String
        let replacement: String
        let boundarySuffix: String
        let previousInputSourceID: String?
        let timestamp: Date
        var totalInsertedLength: Int { replacement.count + boundarySuffix.count }
    }

    init() {
        if let storedMode = UserDefaults.standard.string(forKey: Self.correctionModeDefaultsKey),
           let correctionMode = CorrectionMode(rawValue: storedMode) {
            self.correctionMode = correctionMode
        } else {
            self.correctionMode = .manual
        }

        if let storedTrigger = UserDefaults.standard.string(forKey: Self.revertTriggerDefaultsKey),
           let trigger = RevertTrigger(rawValue: storedTrigger) {
            self.revertTrigger = trigger
        } else {
            self.revertTrigger = .rightCommand
        }

        refreshPermissions(prompt: true)
        setupBindings()
        typingMonitor.shouldInterceptDelete = { [weak self] in
            guard let self else { return false }
            return self.revertTrigger == .delete && self.isRevertPending()
        }
        typingMonitor.onInterceptedDelete = { [weak self] in
            // Hop to main to do the AX work — tap callback runs on main already,
            // but this keeps the semantics explicit.
            Task { @MainActor in self?.revertLastCorrection() }
        }
        typingMonitor.onRightCommandTap = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard self.revertTrigger == .rightCommand, self.isRevertPending() else { return }
                self.revertLastCorrection()
            }
        }
        typingMonitor.start()
        registerHotKey()
    }

    deinit {
        applyHotKey?.unregister()
        typingMonitor.stop()
    }

    func refreshPermissions(prompt: Bool = false) {
        hasAccessibilityPermission = PermissionController.checkAccessibility(prompt: prompt)
        hasInputMonitoringPermission = PermissionController.checkInputMonitoring()
        if prompt && !hasInputMonitoringPermission {
            PermissionController.requestInputMonitoring()
        }
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
        let currentInputSource = inputSourceController.currentInputSourceID() ?? "(nil)"
        NSLog("[Langsense] boundary seen token=%@ tokenLen=%d suffix=%@ inputSource=%@ mode=%@",
              snapshot.token, snapshot.token.count, snapshot.boundarySuffix, currentInputSource, correctionMode.rawValue)

        guard correctionMode == .boundaryAutoFix,
              !shouldSuppressAutoCorrection(for: snapshot.token) else {
            return
        }

        guard let boundarySuggestion = ConversionEngine.suggest(for: snapshot.token, profile: .boundaryAutoFix) else {
            NSLog("[Langsense] boundary no-suggestion token=%@", snapshot.token)
            return
        }

        NSLog("[Langsense] boundary fire token=%@ replacement=%@ suffix=%@", snapshot.token, boundarySuggestion.replacement, snapshot.boundarySuffix)

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

        NSLog("[Langsense] aggressive fire token=%@ replacement=%@ deleteCount=%d confidence=%.3f", token, aggressiveSuggestion.replacement, aggressiveSuggestion.deleteCount, aggressiveSuggestion.confidence)

        _ = performCorrection(
            suggestion: aggressiveSuggestion,
            deleteCount: aggressiveSuggestion.deleteCount,
            replacement: aggressiveSuggestion.replacement,
            resultingToken: "",
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

        if TextReplacementService.isSecureInputActive() {
            lastActionMessage = "Skipped: secure input is active (password field or terminal)."
            return false
        }

        let previousInputSource = inputSourceController.currentInputSourceID()
        let sourceChanged = inputSourceController.selectInputSource(for: suggestion.targetLanguage)
        let postSwitchID = inputSourceController.currentInputSourceID() ?? "(nil)"
        NSLog("[Langsense] ime switch target=%@ previous=%@ returned=%@ postSwitchID=%@", suggestion.targetLanguage.rawValue, previousInputSource ?? "(nil)", sourceChanged ? "true" : "false", postSwitchID)
        guard sourceChanged else {
            lastActionMessage = "Could not switch to \(suggestion.targetLanguage.rawValue) input source."
            return false
        }

        typingMonitor.prepareForProgrammaticReplacement(resultingToken: resultingToken)

        let outcome = textReplacer.replaceRecentText(deleteCount: deleteCount, replacement: replacement)
        NSLog("[Langsense] replacement outcome=%@ deleteCount=%d replacement=%@", String(describing: outcome), deleteCount, replacement)
        switch outcome {
        case .success:
            break
        case .secureInputActive:
            if let previousInputSource,
               previousInputSource != inputSourceController.currentInputSourceID() {
                _ = inputSourceController.selectInputSource(id: previousInputSource)
            }
            lastActionMessage = "Skipped: secure input became active during replacement."
            return false
        case .failed:
            if let previousInputSource,
               previousInputSource != inputSourceController.currentInputSourceID() {
                _ = inputSourceController.selectInputSource(id: previousInputSource)
            }
            lastActionMessage = "Could not replace text in the focused app. Restored the previous input source when possible."
            return false
        }

        rememberCorrection(original: suggestion.original, replacement: suggestion.replacement)
        if let consumeExpectedToken {
            typingMonitor.consumeLastToken(expected: consumeExpectedToken)
        }

        let suffix = String(replacement.dropFirst(suggestion.replacement.count))
        lastCorrection = LastCorrection(
            original: suggestion.original,
            replacement: suggestion.replacement,
            boundarySuffix: suffix,
            previousInputSourceID: previousInputSource,
            timestamp: Date()
        )

        self.pendingBoundarySuffix = ""
        let percent = Int((suggestion.confidence * 100).rounded())
        self.lastActionMessage = "\(messagePrefix) ‘\(suggestion.original)’ → ‘\(suggestion.replacement)’ (\(percent)% confidence). Press Delete within 1.5s to undo + learn."
        self.recentToken = resultingToken
        self.suggestion = manualSuggestion(for: resultingToken)
        return true
    }

    func revertLastCorrection() {
        guard let correction = lastCorrection else {
            lastActionMessage = "Nothing to revert."
            return
        }
        guard Date().timeIntervalSince(correction.timestamp) <= Self.revertWindow else {
            lastActionMessage = "Revert window expired."
            lastCorrection = nil
            return
        }
        guard hasAccessibilityPermission else {
            lastActionMessage = "Accessibility permission required to revert."
            return
        }
        if TextReplacementService.isSecureInputActive() {
            lastActionMessage = "Skipped revert: secure input is active."
            return
        }

        typingMonitor.prepareForProgrammaticReplacement(resultingToken: "")

        let outcome = textReplacer.replaceRecentText(
            deleteCount: correction.totalInsertedLength,
            replacement: correction.original + correction.boundarySuffix
        )
        NSLog("[Langsense] revert outcome=%@", String(describing: outcome))
        guard case .success = outcome else {
            lastActionMessage = "Could not revert text in the focused app."
            return
        }

        if let previous = correction.previousInputSourceID,
           previous != inputSourceController.currentInputSourceID() {
            _ = inputSourceController.selectInputSource(id: previous)
        }

        blocklist.insert(correction.original)
        correctedTokens.removeValue(forKey: normalizedToken(correction.original))
        correctedTokens.removeValue(forKey: normalizedToken(correction.replacement))

        lastActionMessage = "Reverted ‘\(correction.replacement)’ → ‘\(correction.original)’ and added to blocklist."
        lastCorrection = nil
        recentToken = ""
        suggestion = nil
    }

    private func manualSuggestion(for token: String) -> ConversionSuggestion? {
        guard !isInCorrectionCooldown(token), !blocklist.contains(token) else { return nil }
        return ConversionEngine.suggest(for: token, profile: .manual)
    }

    private func shouldSuppressAutoCorrection(for token: String) -> Bool {
        token.isEmpty || isInCorrectionCooldown(token) || blocklist.contains(token)
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
            correctedTokens = Dictionary(uniqueKeysWithValues: sorted.prefix(Self.correctedTokenCacheLimit).map { ($0.key, $0.value) })
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
        applyHotKey = HotKeyController(
            keyCode: UInt16(kVK_Return),
            modifierFlags: [.control, .option, .command]
        ) { [weak self] in
            Task { @MainActor in
                self?.applySuggestion()
            }
        }
        applyHotKey?.register()
    }

    private func isRevertPending() -> Bool {
        guard let correction = lastCorrection else { return false }
        return Date().timeIntervalSince(correction.timestamp) <= Self.revertWindow
    }
}
