import XCTest
@testable import Langsense

final class ConversionEngineTests: XCTestCase {
    func testEnglishToKoreanConversion() {
        XCTAssertEqual(ConversionEngine.englishToKorean("dkssudgktpdy"), "안녕하세요")
    }

    func testKoreanToEnglishConversion() {
        XCTAssertEqual(ConversionEngine.koreanToEnglish("ㅗ디ㅣㅐ"), "hello")
    }

    func testManualSuggestionStillFindsStrongMistype() {
        let suggestion = ConversionEngine.suggest(for: "dkssudgktpdy", profile: .manual)
        XCTAssertEqual(suggestion?.replacement, "안녕하세요")
        XCTAssertEqual(suggestion?.targetLanguage, .korean)
    }

    func testBoundaryAutoRejectsOrdinaryEnglishWord() {
        XCTAssertNil(ConversionEngine.suggest(for: "hello", profile: .boundaryAutoFix))
        XCTAssertNil(ConversionEngine.suggest(for: "keyboard", profile: .boundaryAutoFix))
    }

    func testAggressiveModeRequiresVeryStrongSignal() {
        XCTAssertNil(ConversionEngine.suggest(for: "dkss", profile: .aggressive))
        XCTAssertNotNil(ConversionEngine.suggest(for: "dkssudgktpdy", profile: .aggressive))
    }

    func testManualSuggestionHandlesKoreanJamoMistype() {
        let suggestion = ConversionEngine.suggest(for: "ㅗ디ㅣㅐ", profile: .manual)
        XCTAssertEqual(suggestion?.replacement, "hello")
        XCTAssertEqual(suggestion?.targetLanguage, .english)
    }

    func testAggressiveModeFiresForLongKoreanJamoMistype() {
        let suggestion = ConversionEngine.suggest(for: "ㅏ색ㅎㅅㅁ색ㄷ", profile: .aggressive)
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.targetLanguage, .english)
    }

    func testBoundaryModeRejectsPartiallyComposedHangulOutput() {
        XCTAssertNil(ConversionEngine.suggest(for: "rhk", profile: .boundaryAutoFix))
    }
}
