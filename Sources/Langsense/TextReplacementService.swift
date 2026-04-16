import AppKit
import ApplicationServices
import Carbon
import Foundation

enum ReplacementOutcome {
    case success
    case secureInputActive
    case failed
}

final class TextReplacementService {
    /// Marker written into `.eventSourceUserData` on every CGEvent we synthesize,
    /// so our own event tap can recognize and ignore them. Without this, the
    /// Delete keystrokes emitted during the paste fallback are re-entrant and
    /// re-trigger the revert path mid-replacement.
    static let syntheticEventMarker: Int64 = 0x4C414E_47_53_4E_53 // 'LANG_SNS'

    static func isSecureInputActive() -> Bool {
        IsSecureEventInputEnabled()
    }

    func replaceRecentText(deleteCount: Int, replacement: String) -> ReplacementOutcome {
        guard deleteCount > 0, !replacement.isEmpty else { return .failed }
        if Self.isSecureInputActive() { return .secureInputActive }

        if tryAccessibilityReplacement(deleteCount: deleteCount, replacement: replacement) {
            return .success
        }

        return performPasteFallback(deleteCount: deleteCount, replacement: replacement) ? .success : .failed
    }

    private func tryAccessibilityReplacement(deleteCount: Int, replacement: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.25)

        var focusedRef: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusErr == .success, let focusedRef else {
            NSLog("[Langsense] AX focus err=%d", focusErr.rawValue)
            return false
        }
        guard CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            NSLog("[Langsense] AX focused ref is not an AXUIElement")
            return false
        }
        let element = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)

        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String,
           subrole == "AXSecureTextField" {
            NSLog("[Langsense] AX skip: focused element is AXSecureTextField")
            return false
        }

        var rangeRef: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        guard rangeErr == .success, let rangeRef else {
            NSLog("[Langsense] AX selected-range err=%d", rangeErr.rawValue)
            return false
        }
        let rangeValue = rangeRef as! AXValue

        var selection = CFRange(location: 0, length: 0)
        guard AXValueGetType(rangeValue) == .cfRange,
              AXValueGetValue(rangeValue, .cfRange, &selection) else {
            NSLog("[Langsense] AX range decode failed")
            return false
        }

        let newLocation = selection.location + selection.length - deleteCount
        guard newLocation >= 0 else {
            NSLog("[Langsense] AX negative newLocation deleteCount=%d selection.location=%d", deleteCount, selection.location)
            return false
        }

        var expanded = CFRange(location: newLocation, length: deleteCount)
        guard let expandedValue = AXValueCreate(.cfRange, &expanded) else { return false }

        let setRangeErr = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, expandedValue)
        guard setRangeErr == .success else {
            NSLog("[Langsense] AX set-range err=%d", setRangeErr.rawValue)
            return false
        }

        let setTextErr = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFString)
        if setTextErr != .success {
            NSLog("[Langsense] AX set-text err=%d", setTextErr.rawValue)
        } else {
            NSLog("[Langsense] AX replace succeeded location=%d length=%d replacement=%@", newLocation, deleteCount, replacement)
        }
        return setTextErr == .success
    }

    private func performPasteFallback(deleteCount: Int, replacement: String) -> Bool {
        NSLog("[Langsense] paste fallback deleteCount=%d replacement=%@", deleteCount, replacement)
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        guard writeReplacement(replacement, to: pasteboard) else {
            snapshot.restore(to: pasteboard)
            return false
        }
        let changeCountAfterWrite = pasteboard.changeCount
        let frontmostAtWrite = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<deleteCount {
                Self.postKeystroke(keyCode: CGKeyCode(kVK_Delete), flags: [], source: source)
            }
            Thread.sleep(forTimeInterval: 0.06)
            Self.postKeystroke(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand, source: source)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Guard: another process wrote to the pasteboard (e.g. user's ⌘C) → their copy wins.
                // Guard: frontmost app changed → don't risk a stale restore into the wrong context.
                let frontmostNow = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                guard pasteboard.changeCount == changeCountAfterWrite,
                      frontmostAtWrite == frontmostNow else {
                    NSLog("[Langsense] skipping pasteboard restore (clipboard or frontmost changed)")
                    return
                }
                snapshot.restore(to: pasteboard)
            }
        }
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

    private static func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags, source: CGEventSource) {
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        keyDown?.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyUp?.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
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
