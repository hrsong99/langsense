import ApplicationServices
import Carbon
import Foundation

final class TypingMonitor: ObservableObject {
    @Published private(set) var snapshot = TypingSnapshot(token: "", justReachedBoundary: false, boundarySuffix: "")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let maxTokenLength = 32
    private let boundaryCharacters = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)

    private var currentToken = ""
    private var ignoredEventsUntil = Date.distantPast

    func start() {
        guard eventTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard type == .keyDown, let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let monitor = Unmanaged<TypingMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.handle(event: event)
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
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
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

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        switch Int(keyCode) {
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
            guard let scalarString = event.unicodeString, scalarString.count == 1 else { return }
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
                currentToken = ""
                publishSnapshot(justReachedBoundary: false, boundarySuffix: "")
            }
        }
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
