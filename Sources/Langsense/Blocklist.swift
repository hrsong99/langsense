import Foundation

/// Persists originals the user has explicitly rejected via the revert hotkey.
/// When the user reverts a correction, the original token is added here so
/// subsequent matches are never corrected again.
final class Blocklist {
    private var entries: Set<String> = []
    private let fileURL: URL?

    init() {
        fileURL = Self.defaultFileURL()
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            entries = Set(decoded)
        }
    }

    func contains(_ original: String) -> Bool {
        entries.contains(Self.normalize(original))
    }

    func insert(_ original: String) {
        let key = Self.normalize(original)
        guard !entries.contains(key) else { return }
        entries.insert(key)
        persist()
    }

    private func persist() {
        guard let fileURL else { return }
        let sorted = entries.sorted()
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(sorted)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[Langsense] blocklist persist failed: %@", error.localizedDescription)
        }
    }

    private static func normalize(_ token: String) -> String {
        token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func defaultFileURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport
            .appendingPathComponent("Langsense", isDirectory: true)
            .appendingPathComponent("blocklist.json")
    }
}
