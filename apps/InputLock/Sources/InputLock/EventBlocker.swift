import CoreGraphics
import Foundation

// Event classes and the tap lifecycle are adapted from CleanMyScreen's
// SystemInputBlocker (MIT, see LICENSE-CleanMyScreen).
final class EventBlocker {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pinnedCursor = CGPoint.zero

    var isActive: Bool { tap != nil }

    func start() -> Bool {
        guard tap == nil else { return true }
        guard let createdTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.inputEventMask,
            callback: eventBlockerCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdTap, 0) else {
            CFMachPortInvalidate(createdTap)
            return false
        }
        tap = createdTap
        runLoopSource = source
        pinnedCursor = CGEvent(source: nil)?.location ?? .zero
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: createdTap, enable: true)
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        runLoopSource = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if Self.cursorMovingEventTypes.contains(type.rawValue) {
            CGWarpMouseCursorPosition(pinnedCursor)
        }
        return nil
    }

    // A pointing device that could not be held still moves the cursor before
    // this tap sees the event, so the cursor is put back where the lock began.
    private static let cursorMovingEventTypes: Set<UInt32> = [
        CGEventType.mouseMoved.rawValue,
        CGEventType.leftMouseDragged.rawValue,
        CGEventType.rightMouseDragged.rawValue,
        CGEventType.otherMouseDragged.rawValue,
    ]

    private static let keyboardEventTypes: [UInt32] = [
        CGEventType.keyDown.rawValue,
        CGEventType.keyUp.rawValue,
        CGEventType.flagsChanged.rawValue,
        14, // NSEvent.EventType.systemDefined: media, brightness and other auxiliary keys
    ]

    private static let pointerEventTypes: [UInt32] = [
        CGEventType.leftMouseDown.rawValue,
        CGEventType.leftMouseUp.rawValue,
        CGEventType.rightMouseDown.rawValue,
        CGEventType.rightMouseUp.rawValue,
        CGEventType.mouseMoved.rawValue,
        CGEventType.leftMouseDragged.rawValue,
        CGEventType.rightMouseDragged.rawValue,
        CGEventType.otherMouseDown.rawValue,
        CGEventType.otherMouseUp.rawValue,
        CGEventType.otherMouseDragged.rawValue,
        CGEventType.tabletPointer.rawValue,
        CGEventType.tabletProximity.rawValue,
        CGEventType.scrollWheel.rawValue,
        34, // pressure
    ]

    // NSEvent raw values CoreGraphics does not name; taps still see them.
    private static let gestureEventTypes: [UInt32] = [18, 19, 20, 29, 30, 31, 32, 37, 38]

    private static let inputEventMask: CGEventMask = (keyboardEventTypes + pointerEventTypes + gestureEventTypes)
        .reduce(0) { $0 | (CGEventMask(1) << CGEventMask($1)) }
}

private func eventBlockerCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventBlocker>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
}
