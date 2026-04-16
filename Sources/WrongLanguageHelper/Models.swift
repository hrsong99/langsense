import Foundation

enum TargetLanguage: String, CaseIterable {
    case english = "English"
    case korean = "Korean"
}

enum CorrectionMode: String, CaseIterable, Identifiable {
    case manual
    case boundaryAutoFix
    case aggressive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual:
            return "Manual"
        case .boundaryAutoFix:
            return "Auto-fix on boundary (Experimental)"
        case .aggressive:
            return "Aggressive mid-word (Experimental)"
        }
    }

    var summary: String {
        switch self {
        case .manual:
            return "Only fix text when you invoke the hotkey or menu action."
        case .boundaryAutoFix:
            return "Experimental. Wait for a word boundary, then auto-fix only when the token strongly looks like wrong-layout input. Safer than aggressive mode, but manual is still safest."
        case .aggressive:
            return "Experimental. Mid-word auto-fix with very strict gating and cooldowns. Fastest, but still the riskiest mode."
        }
    }
}

struct ConversionSuggestion: Identifiable, Equatable {
    let id = UUID()
    let original: String
    let replacement: String
    let targetLanguage: TargetLanguage
    let deleteCount: Int
    let reason: String
    let confidence: Double
}

struct TypingSnapshot: Equatable {
    let token: String
    let justReachedBoundary: Bool
    let boundarySuffix: String
}
