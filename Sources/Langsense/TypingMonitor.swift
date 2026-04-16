import AppKit
import ApplicationServices
import Carbon
import Foundation

final class TypingMonitor: ObservableObject {
    @Published private(set) var snapshot = TypingSnapshot(token: "", justReachedBoundary: false, boundarySuffix: "")

    /// Returns true if the next Delete keypress should be consumed by the app
    /// (suppressing it from the target text field) and routed to
    /// `onInterceptedDelete`. Called synchronously from the event tap callback.
    var shouldInterceptDelete: (() -> Bool)?
    var onInterceptedDelete: (() -> Void)?

    /// Fired when the user presses and releases the right ⌘ key alone
    /// (no chord, no other modifier, released inside `rightCommandTapWindow`).
    /// AppState decides whether to act on it based on the user's RevertTrigger setting.
    var onRightCommandTap: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var workspaceObserver: NSObjectProtocol?
    private let maxTokenLength = 32
    private let boundaryCharacters = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    private let rightCommandTapWindow: TimeInterval = 0.5

    private var currentToken = ""
    private var ignoredEventsUntil = Date.distantPast
    private var rightCommandDown = false
    private var rightCommandDownAt = Date.distantPast
    private var rightCommandChordUsed = false

    private static let navigationKeyCodes: Set<Int> = [
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_Escape,
        kVK_ForwardDelete
    ]

    func start() {
        guard eventTap == nil else { return }
        let interestingTypes: [CGEventType] = [
            .keyDown, .flagsChanged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel
        ]
        let mask = interestingTypes.reduce(CGEventMask(0)) { acc, type in
            acc | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<TypingMonitor>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                // macOS disables taps that take too long; re-enable immediately.
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            // Ignore events we synthesized ourselves (paste-fallback Deletes/⌘V).
            // Without this, our own Delete keystrokes re-enter the Delete intercept
            // below and trigger a bogus revert mid-replacement.
            if event.getIntegerValueField(.eventSourceUserData) == TextReplacementService.syntheticEventMarker {
                return Unmanaged.passUnretained(event)
            }

            switch type {
            case .keyDown:
                let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
                // Any real keystroke while Right ⌘ is held turns the gesture into a chord.
                if monitor.rightCommandDown {
                    monitor.rightCommandChordUsed = true
                }
                if keyCode == kVK_Delete,
                   monitor.shouldInterceptDelete?() == true {
                    monitor.onInterceptedDelete?()
                    return nil
                }
                monitor.handle(event: event)
            case .flagsChanged:
                monitor.handleFlagsChanged(event: event)
            case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
                monitor.resetRightCommandState()
                monitor.invalidateToken()
            default:
                break
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
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

    // Right ⌘ tap detection. Fires onRightCommandTap when the user presses
    // and releases the right-Command key alone (no chord, no other modifier,
    // release inside rightCommandTapWindow). AppState decides whether to act
    // on it based on the user's RevertTrigger setting.
    private func handleFlagsChanged(event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        guard keyCode == kVK_RightCommand else {
            // A different modifier changed state. If it happened while Right ⌘
            // was held, the user is chording — disqualify the tap.
            if rightCommandDown {
                rightCommandChordUsed = true
            }
            return
        }

        let commandHeldNow = flags.contains(.maskCommand)
        if commandHeldNow && !rightCommandDown {
            // Any other modifier already pressed when Right ⌘ went down = chord.
            let otherModifiers: CGEventFlags = [.maskShift, .maskAlternate, .maskControl, .maskSecondaryFn, .maskHelp]
            rightCommandDown = true
            rightCommandDownAt = Date()
            rightCommandChordUsed = flags.intersection(otherModifiers).rawValue != 0
        } else if !commandHeldNow && rightCommandDown {
            let heldFor = Date().timeIntervalSince(rightCommandDownAt)
            let wasTap = !rightCommandChordUsed && heldFor <= rightCommandTapWindow
            resetRightCommandState()
            if wasTap {
                onRightCommandTap?()
            }
        }
    }

    private func resetRightCommandState() {
        rightCommandDown = false
        rightCommandChordUsed = false
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
        resetRightCommandState()
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
