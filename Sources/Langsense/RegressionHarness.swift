import Foundation

enum RegressionHarness {
    private static let englishFalsePositives: [String] = [
        "check", "world", "sight", "night", "light", "right", "might", "tight", "write",
        "doesn", "hello", "about", "typing", "coding", "testing", "simple",
        "keyboard", "space", "woman", "board", "music", "learn"
    ]

    private static let englishToKoreanTruePositives: [(String, String)] = [
        ("dkssud",        "안녕"),
        ("dkssudgktpdy",  "안녕하세요"),
        ("rkatkgkqslek",  "감사합니다"),
        ("tkfkdgo",       "사랑해"),
        ("gksrnr",        "한국")
    ]

    private static let koreanToEnglishTruePositives: [(String, String)] = [
        ("ㅗㄷㅣㅣㅐ",         "hello"),
        ("ㅏㄷㅛㅠㅐㅁㄱㅇ", "keyboard")
    ]

    /// Verifies Korean→English suggestions use the composed visible length for deleteCount,
    /// so replacement doesn't eat into the user's previous text.
    private static let koreanToEnglishDeleteCounts: [(String, Int)] = [
        ("ㅗㄷㅣㅣㅐ",         4),  // composes to "ㅗ디ㅣㅐ" (4 on-screen chars)
        ("ㅏㄷㅛㅠㅐㅁㄱㅇ",  7)   // composes to "ㅏ됴ㅠㅐㅁㄱㅇ" (7 on-screen chars)
    ]

    private static let koreanCasualTokens: [String] = [
        "ㅋㅋㅋ", "ㅋㅋㅋㅋ", "ㅎㅎㅎ", "ㅠㅠ", "ㅜㅜ"
    ]

    private static let profiles: [(name: String, profile: SuggestionProfile)] = [
        ("manual", .manual),
        ("boundary", .boundaryAutoFix)
    ]

    @discardableResult
    static func run() -> Bool {
        var passed = 0
        var failed = 0

        func record(_ label: String, _ ok: Bool, detail: String = "") {
            if ok {
                passed += 1
                print("  PASS  \(label)")
            } else {
                failed += 1
                print("  FAIL  \(label)\(detail.isEmpty ? "" : "  — \(detail)")")
            }
        }

        print("== English words that must not convert ==")
        for (name, profile) in profiles {
            for word in englishFalsePositives {
                let result = ConversionEngine.suggest(for: word, profile: profile)
                record("[\(name)] \(word) → nil", result == nil, detail: result.map { "got \($0.replacement)" } ?? "")
            }
        }

        print("== Korean mistypes that must convert ==")
        for (name, profile) in profiles {
            for (input, expected) in englishToKoreanTruePositives {
                let result = ConversionEngine.suggest(for: input, profile: profile)
                let ok = result?.replacement == expected && result?.targetLanguage == .korean
                record("[\(name)] \(input) → \(expected)", ok, detail: result.map { "got \($0.replacement)" } ?? "got nil")
            }
        }

        print("== Hangul-typed English that must convert back ==")
        for (name, profile) in profiles {
            for (input, expected) in koreanToEnglishTruePositives {
                let result = ConversionEngine.suggest(for: input, profile: profile)
                let ok = result?.replacement == expected && result?.targetLanguage == .english
                record("[\(name)] \(input) → \(expected)", ok, detail: result.map { "got \($0.replacement)" } ?? "got nil")
            }
        }

        print("== Korean→English deleteCount uses composed visible length ==")
        for (input, expectedCount) in koreanToEnglishDeleteCounts {
            let result = ConversionEngine.suggest(for: input, profile: .manual)
            let ok = result?.deleteCount == expectedCount
            record("[manual] \(input) → deleteCount=\(expectedCount)", ok, detail: result.map { "got \($0.deleteCount)" } ?? "got nil")
        }

        print("== Korean casual tokens that must not convert ==")
        for (name, profile) in profiles {
            for token in koreanCasualTokens {
                let result = ConversionEngine.suggest(for: token, profile: profile)
                record("[\(name)] \(token) → nil", result == nil, detail: result.map { "got \($0.replacement)" } ?? "")
            }
        }

        let total = passed + failed
        print("\n\(passed)/\(total) passed, \(failed) failed")
        return failed == 0
    }
}
