import AppKit
import Carbon
import Foundation

final class TextReplacementService {
    func replaceRecentText(deleteCount: Int, replacement: String) -> Bool {
        guard deleteCount > 0, !replacement.isEmpty else { return false }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        guard writeReplacement(replacement, to: pasteboard) else {
            snapshot.restore(to: pasteboard)
            return false
        }

        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                snapshot.restore(to: pasteboard)
            }
        }

        for _ in 0..<deleteCount {
            postKeystroke(keyCode: CGKeyCode(kVK_Delete), flags: [], source: source)
        }

        usleep(80_000)
        postKeystroke(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand, source: source)
        return true
    }

    private func writeReplacement(_ replacement: String, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        guard item.setString(replacement, forType: .string) else {
            return false
        }
        return pasteboard.writeObjects([item])
    }

    private func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags, source: CGEventSource) {
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyUp?.post(tap: .cghidEventTap)
    }
}

private struct PasteboardSnapshot {
    struct SavedItem {
        let typeData: [(NSPasteboard.PasteboardType, Data)]
    }

    let items: [SavedItem]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            let typeData = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
            return SavedItem(typeData: typeData)
        }

        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        let restoredItems: [NSPasteboardItem] = items.compactMap { savedItem in
            let item = NSPasteboardItem()
            for (type, data) in savedItem.typeData {
                item.setData(data, forType: type)
            }
            return item.types.isEmpty ? nil : item
        }

        guard !restoredItems.isEmpty else { return }
        pasteboard.writeObjects(restoredItems)
    }
}
