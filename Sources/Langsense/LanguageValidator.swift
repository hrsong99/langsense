import AppKit
import Foundation

enum LanguageValidator {
    private static let checker = NSSpellChecker.shared
    private static var englishValidCache: [String: Bool] = [:]
    private static var englishPrefixCache: [String: Bool] = [:]
    private static var koreanValidCache: [String: Bool] = [:]
    private static let cacheLimit = 512

    static var englishDictionaryAvailable: Bool {
        NSSpellChecker.shared.availableLanguages.contains { $0.hasPrefix("en") }
    }

    static var koreanDictionaryAvailable: Bool {
        NSSpellChecker.shared.availableLanguages.contains { $0.hasPrefix("ko") }
    }

    static func isValidEnglish(_ token: String) -> Bool {
        guard englishDictionaryAvailable, !token.isEmpty else { return false }
        if let cached = englishValidCache[token] { return cached }
        let range = checker.checkSpelling(
            of: token,
            startingAt: 0,
            language: "en",
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        let result = range.location == NSNotFound
        record(&englishValidCache, key: token, value: result)
        return result
    }

    static func isEnglishPrefix(_ token: String) -> Bool {
        guard englishDictionaryAvailable, !token.isEmpty else { return false }
        if let cached = englishPrefixCache[token] { return cached }
        let range = NSRange(location: 0, length: (token as NSString).length)
        let completions = checker.completions(
            forPartialWordRange: range,
            in: token,
            language: "en",
            inSpellDocumentWithTag: 0
        )
        let result = (completions?.isEmpty == false)
        record(&englishPrefixCache, key: token, value: result)
        return result
    }

    static func isValidKorean(_ token: String) -> Bool {
        guard koreanDictionaryAvailable, !token.isEmpty else { return false }
        if let cached = koreanValidCache[token] { return cached }
        let range = checker.checkSpelling(
            of: token,
            startingAt: 0,
            language: "ko",
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        let result = range.location == NSNotFound
        record(&koreanValidCache, key: token, value: result)
        return result
    }

    private static func record(_ cache: inout [String: Bool], key: String, value: Bool) {
        if cache.count >= cacheLimit {
            cache.removeAll(keepingCapacity: true)
        }
        cache[key] = value
    }
}
