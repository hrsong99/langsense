import Carbon
import Foundation

final class InputSourceController {
    func currentInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return property(source, key: kTISPropertyInputSourceID)
    }

    func selectInputSource(for language: TargetLanguage) -> Bool {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return false
        }

        let chosenSource = sources.first { source in
            let id = property(source, key: kTISPropertyInputSourceID) ?? ""
            let localizedName = property(source, key: kTISPropertyLocalizedName) ?? ""
            switch language {
            case .english:
                // Match common English-producing keyboard layouts. "ABC" is the
                // macOS default for US users. "U.S." is the legacy US layout.
                // Also accept USExtended, British, Australian, etc. via the
                // English-language marker in the localized name.
                let englishIDs: Set<String> = [
                    "com.apple.keylayout.ABC",
                    "com.apple.keylayout.US",
                    "com.apple.keylayout.USExtended",
                    "com.apple.keylayout.British",
                    "com.apple.keylayout.British-PC",
                    "com.apple.keylayout.Australian",
                    "com.apple.keylayout.Canadian",
                    "com.apple.keylayout.Irish"
                ]
                if englishIDs.contains(id) { return true }
                let haystack = "\(id) \(localizedName)".lowercased()
                return haystack.contains("english") || localizedName == "ABC" || localizedName == "U.S."
            case .korean:
                let haystack = "\(id) \(localizedName)".lowercased()
                return haystack.contains("korean") || haystack.contains("2-set") || haystack.contains("두벌")
            }
        }

        guard let chosenSource else { return false }
        return TISSelectInputSource(chosenSource) == noErr
    }

    func selectInputSource(id: String) -> Bool {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource],
              let chosenSource = sources.first(where: { property($0, key: kTISPropertyInputSourceID) == id }) else {
            return false
        }

        return TISSelectInputSource(chosenSource) == noErr
    }

    private func property(_ source: TISInputSource, key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFTypeRef>.fromOpaque(raw).takeUnretainedValue() as? String
    }
}
