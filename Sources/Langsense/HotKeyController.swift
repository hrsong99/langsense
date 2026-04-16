import AppKit
import Foundation

final class HotKeyController {
    private let keyCode: UInt16
    private let modifierFlags: NSEvent.ModifierFlags
    private let callback: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, callback: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.callback = callback
    }

    func register() {
        guard globalMonitor == nil, localMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.fireIfMatches(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.fireIfMatches(event) == true else { return event }
            return nil
        }
    }

    func unregister() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    private func fireIfMatches(_ event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else { return false }
        let relevantMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard event.modifierFlags.intersection(relevantMask) == modifierFlags else { return false }
        callback()
        return true
    }
}
