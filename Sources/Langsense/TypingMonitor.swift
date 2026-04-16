import AppKit
import ApplicationServices
import Carbon
import Foundation

final class TypingMonitor: ObservableObject {
    @Published private(set) var snapshot = TypingSnapshot(token: "", justReachedBoundary: false, boundarySuffix: "")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var workspaceObserver: NSObjectProtocol?
    private let maxTokenLength = 32
    private let boundaryCharacters = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)

    private var currentToken = ""
    private var ignoredEventsUntil = Date.distantPast

    private static let navigationKeyCodes: Set<Int> = [
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_Escape,
        kVK_ForwardDelete
    ]

    func start() {
        guard eventTap == nil else { return }
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)
        )
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<TypingMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            switch type {
            case .keyDown:
                monitor.handle(event: event)
            case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
                monitor.invalidateToken()
            default:
                break
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            NSLog("[Langsense] CGEvent.tapCreate failed — Input Monitoring likely not granted to this binary")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.forceInvalidateToken()
        }
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        eventTap = nil
        runLoopSource = nil
        workspaceObserver = nil
    }

    func consumeLastToken(expected: String) {
        if currentToken == expected {
            currentToken = ""
            publishSnapshot(justReachedBoundary: false, boundarySuffix: "")
        }
    }

    func prepareForProgrammaticReplacement(resultingToken: String, ignoreFor seconds: TimeInterval = 0.35) {
        ignoredEventsUntil = Date().addingTimeInterval(seconds)
        currentToken = resultingToken
        publishSnapshot(justReachedBoundary: false, boundarySuffix: "")
    }

    private func handle(event: CGEvent) {
        guard Date() >= ignoredEventsUntil else { return }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        if Self.navigationKeyCodes.contains(keyCode) {
            invalidateToken()
            return
        }

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            invalidateToken()
            return
        }

        switch keyCode {
        case kVK_Delete:
            guard !currentToken.isEmpty else { return }
            currentToken.removeLast()
            publishSnapshot(justReachedBoundary: false, boundarySuffix: "")
        case kVK_Return:
            publishBoundaryAndReset(with: "\n")
        case kVK_Space:
            publishBoundaryAndReset(with: " ")
        case kVK_Tab:
            publishBoundaryAndReset(with: "\t")
        default:
            guard let scalarString = event.unicodeString else {
                invalidateToken()
                return
            }
            if scalarString.count != 1 {
                // Dead-key sequences, emoji, IME commit events — treat as a token break.
                invalidateToken()
                return
            }
            let character = scalarString.first!
            if character.isLetter || character.isHangulCompatibilityJamo || character.isHangulSyllable {
                currentToken.append(character)
                if currentToken.count > maxTokenLength {
                    currentToken.removeFirst(currentToken.count - maxTokenLength)
                }
                publishSnapshot(justReachedBoundary: false, boundarySuffix: "")
            } else if scalarString.rangeOfCharacter(from: boundaryCharacters) != nil {
                publishBoundaryAndReset(with: scalarString)
            } else {
                invalidateToken()
            }
        }
    }

    // All state mutation must happen on the main run loop.
    // The event tap is added via CFRunLoopAddSource(CFRunLoopGetMain()),
    // and the workspace observer's queue is .main.
    private func invalidateToken() {
        guard Date() >= ignoredEventsUntil else { return }
        guard !currentToken.isEmpty else { return }
        currentToken = ""
        publishSnapshot(justReachedBoundary: false, boundarySuffix: "")
    }

    // Skips the ignoredEventsUntil window — used when we have external evidence
    // of focus change (e.g. app activation) that should override any in-flight replacement.
    private func forceInvalidateToken() {
        guard !currentToken.isEmpty else { return }
        currentToken = ""
        publishSnapshot(justReachedBoundary: false, boundarySuffix: "")
    }

    private func publishBoundaryAndReset(with suffix: String) {
        let token = currentToken
        snapshot = TypingSnapshot(token: token, justReachedBoundary: true, boundarySuffix: suffix)
        currentToken = ""
    }

    private func publishSnapshot(justReachedBoundary: Bool, boundarySuffix: String) {
        snapshot = TypingSnapshot(token: currentToken, justReachedBoundary: justReachedBoundary, boundarySuffix: boundarySuffix)
    }
}

private extension CGEvent {
    var unicodeString: String? {
        var length: Int = 0
        keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        guard length > 0 else { return nil }
        var buffer = [UniChar](repeating: 0, count: length)
        keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &buffer)
        return String(utf16CodeUnits: buffer, count: length)
    }
}
