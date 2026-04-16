import XCTest
@testable import Langsense

/// Regression matrix of real-world typing cases.
/// Tests the two modes users actually reach for: `.manual` (default, safest) and
/// `.boundaryAutoFix` (the recommended automatic mode after aggressive was retired).
final class RealisticCasesTests: XCTestCase {

    // MARK: - English tokens that must NEVER convert to Korean
    // These are common English words that previously produced valid-looking Hangul.

    private static let englishFalsePositives: [String] = [
        "check",   // → 촏차 in pure heuristic
        "world",   // → 재깅
        "sight",   // → 냐홋
        "night",
        "light",
        "right",
        "might",
        "tight",
        "write",
        "doesn",   // prefix of doesn't — splits on apostrophe in typing monitor
        "hello",
        "about",
        "typing",
        "coding",
        "testing",
        "simple",
        "keyboard",
        "space",
        "woman",
        "board",
        "music",
        "board",
        "learn"
    ]

    func testEnglishFalsePositivesAreNotConvertedManual() {
        for word in Self.englishFalsePositives {
            let suggestion = ConversionEngine.suggest(for: word, profile: .manual)
            XCTAssertNil(
                suggestion,
                "Manual mode should not convert real English word \"\(word)\", but got \(String(describing: suggestion?.replacement))"
            )
        }
    }

    func testEnglishFalsePositivesAreNotConvertedBoundary() {
        for word in Self.englishFalsePositives {
            let suggestion = ConversionEngine.suggest(for: word, profile: .boundaryAutoFix)
            XCTAssertNil(
                suggestion,
                "Boundary mode should not convert real English word \"\(word)\", but got \(String(describing: suggestion?.replacement))"
            )
        }
    }

    // MARK: - Korean mistypes (English IME active, user meant Korean) that MUST convert

    private static let englishToKoreanTruePositives: [(input: String, expected: String)] = [
        ("dkssud",        "안녕"),          // hello (informal)
        ("dkssudgktpdy",  "안녕하세요"),    // hello (formal)
        ("rkatkgkqslek",  "감사합니다"),    // thank you
        ("tkfkdgo",       "사랑해"),        // love
        ("gksrnr",        "한국")           // Korea
    ]

    func testKoreanMistypesConvertCorrectlyManual() {
        for (input, expected) in Self.englishToKoreanTruePositives {
            let suggestion = ConversionEngine.suggest(for: input, profile: .manual)
            XCTAssertEqual(
                suggestion?.replacement,
                expected,
                "Manual mode should convert \"\(input)\" → \"\(expected)\""
            )
            XCTAssertEqual(suggestion?.targetLanguage, .korean)
        }
    }

    func testKoreanMistypesConvertCorrectlyBoundary() {
        for (input, expected) in Self.englishToKoreanTruePositives {
            let suggestion = ConversionEngine.suggest(for: input, profile: .boundaryAutoFix)
            XCTAssertEqual(
                suggestion?.replacement,
                expected,
                "Boundary mode should convert \"\(input)\" → \"\(expected)\""
            )
        }
    }

    // MARK: - Hangul-typed English (Korean IME active, user meant English)

    private static let koreanToEnglishTruePositives: [(input: String, expected: String)] = [
        ("ㅗㄷㅣㅣㅐ",          "hello"),
        ("ㅏㄷㅛㅠㅐㅁㄱㅇ",  "keyboard")
    ]

    func testHangulTypedEnglishConvertsBackManual() {
        for (input, expected) in Self.koreanToEnglishTruePositives {
            let suggestion = ConversionEngine.suggest(for: input, profile: .manual)
            XCTAssertEqual(
                suggestion?.replacement,
                expected,
                "Manual mode should convert hangul-typed \"\(input)\" → \"\(expected)\""
            )
            XCTAssertEqual(suggestion?.targetLanguage, .english)
        }
    }

    // MARK: - Korean casual tokens that should NEVER convert

    private static let koreanCasualTokens: [String] = [
        "ㅋㅋㅋ",   // laughter
        "ㅋㅋㅋㅋ",
        "ㅎㅎㅎ",
        "ㅠㅠ",
        "ㅜㅜ"
    ]

    func testKoreanCasualTokensAreNotConverted() {
        for token in Self.koreanCasualTokens {
            let manual = ConversionEngine.suggest(for: token, profile: .manual)
            let boundary = ConversionEngine.suggest(for: token, profile: .boundaryAutoFix)
            XCTAssertNil(manual, "Manual mode should not convert casual \"\(token)\"")
            XCTAssertNil(boundary, "Boundary mode should not convert casual \"\(token)\"")
        }
    }
}
