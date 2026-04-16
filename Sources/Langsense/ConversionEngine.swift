import Foundation

enum SuggestionProfile {
    case manual
    case boundaryAutoFix
    case aggressive

    var minimumConfidence: Double {
        switch self {
        case .manual:
            return 0.72
        case .boundaryAutoFix:
            return 0.97
        case .aggressive:
            return 0.995
        }
    }

    var minimumTokenLength: Int {
        switch self {
        case .manual:
            return 2
        case .boundaryAutoFix:
            return 5
        case .aggressive:
            return 6
        }
    }

    var requiresFullyComposedHangulOutput: Bool {
        switch self {
        case .manual:
            return false
        case .boundaryAutoFix, .aggressive:
            return true
        }
    }

    var minimumHangulSyllableRatio: Double {
        switch self {
        case .manual:
            return 0.6
        case .boundaryAutoFix:
            return 0.9
        case .aggressive:
            return 0.95
        }
    }

    var minimumASCIIAlphaRatio: Double {
        switch self {
        case .manual:
            return 0.9
        case .boundaryAutoFix:
            return 0.98
        case .aggressive:
            return 1.0
        }
    }

    var maximumNormalizedReplacementPenalty: Double {
        switch self {
        case .manual:
            return 0.5
        case .boundaryAutoFix:
            return 0.18
        case .aggressive:
            return 0.08
        }
    }
}

enum ConversionEngine {
    private static let latinToJamo: [Character: String] = [
        "q": "ㅂ", "w": "ㅈ", "e": "ㄷ", "r": "ㄱ", "t": "ㅅ", "y": "ㅛ", "u": "ㅕ", "i": "ㅑ", "o": "ㅐ", "p": "ㅔ",
        "a": "ㅁ", "s": "ㄴ", "d": "ㅇ", "f": "ㄹ", "g": "ㅎ", "h": "ㅗ", "j": "ㅓ", "k": "ㅏ", "l": "ㅣ",
        "z": "ㅋ", "x": "ㅌ", "c": "ㅊ", "v": "ㅍ", "b": "ㅠ", "n": "ㅜ", "m": "ㅡ",
        "Q": "ㅃ", "W": "ㅉ", "E": "ㄸ", "R": "ㄲ", "T": "ㅆ", "O": "ㅒ", "P": "ㅖ"
    ]

    private static let initialIndex: [String: Int] = [
        "ㄱ": 0, "ㄲ": 1, "ㄴ": 2, "ㄷ": 3, "ㄸ": 4, "ㄹ": 5, "ㅁ": 6, "ㅂ": 7, "ㅃ": 8, "ㅅ": 9,
        "ㅆ": 10, "ㅇ": 11, "ㅈ": 12, "ㅉ": 13, "ㅊ": 14, "ㅋ": 15, "ㅌ": 16, "ㅍ": 17, "ㅎ": 18
    ]

    private static let medialIndex: [String: Int] = [
        "ㅏ": 0, "ㅐ": 1, "ㅑ": 2, "ㅒ": 3, "ㅓ": 4, "ㅔ": 5, "ㅕ": 6, "ㅖ": 7, "ㅗ": 8, "ㅘ": 9,
        "ㅙ": 10, "ㅚ": 11, "ㅛ": 12, "ㅜ": 13, "ㅝ": 14, "ㅞ": 15, "ㅟ": 16, "ㅠ": 17, "ㅡ": 18, "ㅢ": 19, "ㅣ": 20
    ]

    private static let finalIndex: [String: Int] = [
        "": 0, "ㄱ": 1, "ㄲ": 2, "ㄳ": 3, "ㄴ": 4, "ㄵ": 5, "ㄶ": 6, "ㄷ": 7, "ㄹ": 8, "ㄺ": 9,
        "ㄻ": 10, "ㄼ": 11, "ㄽ": 12, "ㄾ": 13, "ㄿ": 14, "ㅀ": 15, "ㅁ": 16, "ㅂ": 17, "ㅄ": 18,
        "ㅅ": 19, "ㅆ": 20, "ㅇ": 21, "ㅈ": 22, "ㅊ": 23, "ㅋ": 24, "ㅌ": 25, "ㅍ": 26, "ㅎ": 27
    ]

    private static let indexToInitial = ["ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]
    private static let indexToMedial = ["ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅘ", "ㅙ", "ㅚ", "ㅛ", "ㅜ", "ㅝ", "ㅞ", "ㅟ", "ㅠ", "ㅡ", "ㅢ", "ㅣ"]
    private static let indexToFinal = ["", "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ", "ㄻ", "ㄼ", "ㄽ", "ㄾ", "ㄿ", "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]

    private static let compoundVowels: [String: String] = [
        "ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ", "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅡㅣ": "ㅢ"
    ]

    private static let compoundFinals: [String: String] = [
        "ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ", "ㄹㅅ": "ㄽ",
        "ㄹㅌ": "ㄾ", "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ"
    ]

    private static let splitFinals: [String: (String, String)] = [
        "ㄳ": ("ㄱ", "ㅅ"), "ㄵ": ("ㄴ", "ㅈ"), "ㄶ": ("ㄴ", "ㅎ"), "ㄺ": ("ㄹ", "ㄱ"), "ㄻ": ("ㄹ", "ㅁ"),
        "ㄼ": ("ㄹ", "ㅂ"), "ㄽ": ("ㄹ", "ㅅ"), "ㄾ": ("ㄹ", "ㅌ"), "ㄿ": ("ㄹ", "ㅍ"), "ㅀ": ("ㄹ", "ㅎ"), "ㅄ": ("ㅂ", "ㅅ")
    ]

    private static let jamoToLatin: [String: String] = [
        "ㄱ": "r", "ㄲ": "R", "ㄴ": "s", "ㄷ": "e", "ㄸ": "E", "ㄹ": "f", "ㅁ": "a", "ㅂ": "q", "ㅃ": "Q", "ㅅ": "t", "ㅆ": "T",
        "ㅇ": "d", "ㅈ": "w", "ㅉ": "W", "ㅊ": "c", "ㅋ": "z", "ㅌ": "x", "ㅍ": "v", "ㅎ": "g",
        "ㅏ": "k", "ㅐ": "o", "ㅑ": "i", "ㅒ": "O", "ㅓ": "j", "ㅔ": "p", "ㅕ": "u", "ㅖ": "P", "ㅗ": "h",
        "ㅘ": "hk", "ㅙ": "ho", "ㅚ": "hl", "ㅛ": "y", "ㅜ": "n", "ㅝ": "nj", "ㅞ": "np", "ㅟ": "nl", "ㅠ": "b", "ㅡ": "m", "ㅢ": "ml", "ㅣ": "l"
    ]

    static func suggest(for token: String) -> ConversionSuggestion? {
        suggest(for: token, profile: .manual)
    }

    static func suggest(for token: String, minimumConfidence: Double) -> ConversionSuggestion? {
        suggest(for: token, profile: .manual, minimumConfidenceOverride: minimumConfidence)
    }

    static func suggest(for token: String, profile: SuggestionProfile) -> ConversionSuggestion? {
        suggest(for: token, profile: profile, minimumConfidenceOverride: nil)
    }

    static func englishToKorean(_ input: String) -> String {
        let jamo = input.compactMap { latinToJamo[$0] }
        return composeHangul(from: jamo)
    }

    static func koreanToEnglish(_ input: String) -> String {
        var output = ""
        for char in input {
            if let scalar = char.unicodeScalars.first?.value, (0xAC00...0xD7A3).contains(Int(scalar)) {
                let syllableIndex = Int(scalar - 0xAC00)
                let initial = syllableIndex / (21 * 28)
                let medial = (syllableIndex % (21 * 28)) / 28
                let final = syllableIndex % 28

                output += jamoToLatin[indexToInitial[initial]] ?? ""
                output += jamoToLatin[indexToMedial[medial]] ?? ""
                let finalJamo = indexToFinal[final]
                if let split = splitFinals[finalJamo] {
                    output += jamoToLatin[split.0] ?? ""
                    output += jamoToLatin[split.1] ?? ""
                } else {
                    output += jamoToLatin[finalJamo] ?? ""
                }
            } else {
                let string = String(char)
                output += jamoToLatin[string] ?? string
            }
        }
        return output
    }

    private static func suggest(for token: String, profile: SuggestionProfile, minimumConfidenceOverride: Double?) -> ConversionSuggestion? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= profile.minimumTokenLength else { return nil }

        let candidates = [
            englishToKoreanSuggestion(for: trimmed, profile: profile),
            koreanToEnglishSuggestion(for: trimmed, profile: profile)
        ].compactMap { $0 }

        let minimumConfidence = minimumConfidenceOverride ?? profile.minimumConfidence
        return candidates.max(by: { $0.confidence < $1.confidence }).flatMap { best in
            best.confidence >= minimumConfidence ? best : nil
        }
    }

    private static func englishToKoreanSuggestion(for token: String, profile: SuggestionProfile) -> ConversionSuggestion? {
        guard token.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }

        if LanguageValidator.isValidEnglish(token) || LanguageValidator.isEnglishPrefix(token) {
            return nil
        }

        let converted = englishToKorean(token)
        let hangulSyllableCount = converted.filter { $0.isHangulSyllable }.count
        let composedRatio = converted.isEmpty ? 0 : Double(hangulSyllableCount) / Double(converted.count)
        let vowelCount = token.filter(isLikelyLatinVowel).count
        let vowelRatio = Double(vowelCount) / Double(token.count)
        let upperCaseRatio = Double(token.filter { $0.isUppercase }.count) / Double(token.count)
        let penalty = englishReplacementPenalty(source: token, replacement: converted, vowelRatio: vowelRatio, uppercaseRatio: upperCaseRatio)
        let heuristicConfidence = min(
            0.999,
            0.54
                + (Double(min(token.count, 10)) * 0.035)
                + (composedRatio * 0.22)
                + ((1.0 - abs(0.42 - vowelRatio)) * 0.09)
                - penalty
        )
        let convertedIsKorean = LanguageValidator.isValidKorean(converted)
        let confidence = convertedIsKorean ? 0.999 : heuristicConfidence

        guard hangulSyllableCount >= max(2, token.count / 3),
              composedRatio >= profile.minimumHangulSyllableRatio,
              (!profile.requiresFullyComposedHangulOutput || hangulSyllableCount == converted.count),
              penalty <= profile.maximumNormalizedReplacementPenalty,
              converted != token else {
            return nil
        }

        return ConversionSuggestion(
            original: token,
            replacement: converted,
            targetLanguage: .korean,
            deleteCount: token.count,
            reason: convertedIsKorean
                ? "Converted output is a recognized Korean word."
                : "Latin letters map unusually cleanly to fully composed Hangul keyboard output.",
            confidence: confidence
        )
    }

    private static func koreanToEnglishSuggestion(for token: String, profile: SuggestionProfile) -> ConversionSuggestion? {
        guard token.containsHangul,
              token.allSatisfy({ $0.isHangulSyllable || $0.isHangulCompatibilityJamo }) else {
            return nil
        }

        if LanguageValidator.isValidKorean(token) {
            return nil
        }

        let converted = koreanToEnglish(token)
        let asciiLetters = converted.filter { $0.isASCII && $0.isLetter }.count
        let asciiRatio = converted.isEmpty ? 0 : Double(asciiLetters) / Double(converted.count)
        let lowerCaseRatio = Double(converted.filter { $0.isLowercase }.count) / Double(max(converted.count, 1))
        let penalty = koreanReplacementPenalty(source: token, replacement: converted)
        let heuristicConfidence = min(
            0.999,
            0.60
                + (Double(min(token.count, 10)) * 0.035)
                + (asciiRatio * 0.22)
                + (lowerCaseRatio * 0.06)
                - penalty
        )
        let convertedIsEnglish = LanguageValidator.isValidEnglish(converted)
        let confidence = convertedIsEnglish ? 0.999 : heuristicConfidence

        guard converted.count >= profile.minimumTokenLength,
              asciiRatio >= profile.minimumASCIIAlphaRatio,
              penalty <= profile.maximumNormalizedReplacementPenalty,
              converted != token else {
            return nil
        }

        // deleteCount must match the visible on-screen length. The Korean IME composes
        // raw jamo into syllables, so `token.count` (raw keystrokes) is typically larger
        // than the number of characters on screen. Using the composed length prevents
        // us from over-deleting into the user's previous text.
        let visibleDeleteCount = ConversionEngine.composedVisibleForm(of: token).count

        return ConversionSuggestion(
            original: token,
            replacement: converted,
            targetLanguage: .english,
            deleteCount: visibleDeleteCount,
            reason: convertedIsEnglish
                ? "Converted output is a recognized English word."
                : "Hangul input maps back to a clean English keyboard sequence with low ambiguity.",
            confidence: confidence
        )
    }

    private static func englishReplacementPenalty(source: String, replacement: String, vowelRatio: Double, uppercaseRatio: Double) -> Double {
        var penalty = 0.0
        let replacementCount = Double(max(replacement.count, 1))
        let jamoCount = Double(replacement.filter { $0.isHangulCompatibilityJamo }.count)
        penalty += (jamoCount / replacementCount) * 0.35

        let repeatedLatinRuns = longestRunLength(in: source)
        if repeatedLatinRuns >= 3 {
            penalty += Double(repeatedLatinRuns - 2) * 0.04
        }

        if vowelRatio < 0.2 || vowelRatio > 0.75 {
            penalty += 0.08
        }

        if uppercaseRatio > 0.34 {
            penalty += 0.08
        }

        return penalty
    }

    private static func koreanReplacementPenalty(source: String, replacement: String) -> Double {
        var penalty = 0.0
        let replacementCount = Double(max(replacement.count, 1))
        let nonLetters = Double(replacement.filter { !($0.isASCII && $0.isLetter) }.count)
        penalty += (nonLetters / replacementCount) * 0.6

        let repeatedRuns = longestRunLength(in: replacement)
        if repeatedRuns >= 4 {
            penalty += Double(repeatedRuns - 3) * 0.05
        }

        let sourceJamoRatio = Double(source.filter { $0.isHangulCompatibilityJamo }.count) / Double(max(source.count, 1))
        if sourceJamoRatio > 0.34 && source.count < 5 {
            penalty += 0.04
        }

        return penalty
    }

    private static func longestRunLength(in text: String) -> Int {
        var longest = 0
        var current = 0
        var previous: Character?

        for character in text {
            if character == previous {
                current += 1
            } else {
                current = 1
                previous = character
            }
            longest = max(longest, current)
        }

        return longest
    }

    private static func isLikelyLatinVowel(_ character: Character) -> Bool {
        "aeiouyAEIOUY".contains(character)
    }

    private static func composeHangul(from jamo: [String]) -> String {
        var result = ""
        var index = 0

        while index < jamo.count {
            let current = jamo[index]

            guard isConsonant(current), index + 1 < jamo.count, isVowel(jamo[index + 1]) else {
                result += current
                index += 1
                continue
            }

            let lead = current
            var vowel = jamo[index + 1]
            var consumed = 2

            if index + 2 < jamo.count, isVowel(jamo[index + 2]), let combined = compoundVowels[vowel + jamo[index + 2]] {
                vowel = combined
                consumed += 1
            }

            var tail = ""
            if index + consumed < jamo.count, isConsonant(jamo[index + consumed]) {
                let firstTail = jamo[index + consumed]
                let nextIndex = index + consumed + 1

                if nextIndex < jamo.count, isVowel(jamo[nextIndex]) {
                    tail = ""
                } else if nextIndex < jamo.count, isConsonant(jamo[nextIndex]), let combinedTail = compoundFinals[firstTail + jamo[nextIndex]] {
                    let afterCombined = nextIndex + 1
                    if afterCombined < jamo.count, isVowel(jamo[afterCombined]) {
                        tail = firstTail
                        consumed += 1
                    } else {
                        tail = combinedTail
                        consumed += 2
                    }
                } else {
                    tail = firstTail
                    consumed += 1
                }
            }

            if let syllable = composeSyllable(lead: lead, vowel: vowel, tail: tail) {
                result.append(syllable)
            } else {
                result += lead + vowel + tail
            }
            index += consumed
        }

        return result
    }

    private static func composeSyllable(lead: String, vowel: String, tail: String) -> Character? {
        guard let l = initialIndex[lead], let v = medialIndex[vowel], let t = finalIndex[tail] else {
            return nil
        }
        let scalar = 0xAC00 + (l * 21 * 28) + (v * 28) + t
        return UnicodeScalar(scalar).map(Character.init)
    }

    private static func isConsonant(_ jamo: String) -> Bool {
        (initialIndex[jamo] != nil || finalIndex[jamo] != nil) && !jamo.isEmpty
    }

    /// Composed on-screen form of a raw-jamo token, matching what the Korean IME
    /// would render. Used to compute the correct deleteCount for Korean→English
    /// replacements (visible-char count, not raw-keystroke count).
    static func composedVisibleForm(of token: String) -> String {
        let jamo = token.map { String($0) }
        return composeHangul(from: jamo)
    }

    private static func isVowel(_ jamo: String) -> Bool {
        medialIndex[jamo] != nil
    }
}

private extension String {
    var containsHangul: Bool {
        contains { character in
            character.unicodeScalars.contains { scalar in
                (0x3131...0x318E).contains(Int(scalar.value)) || (0xAC00...0xD7A3).contains(Int(scalar.value))
            }
        }
    }
}
