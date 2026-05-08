import Cocoa

final class HotkeyManager {
    var onPress: ((ProcessingMode) -> Void)?
    var onRelease: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false

    func setup() -> Bool {
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo!).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = manager.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            guard event.getIntegerValueField(.keyboardEventKeycode) == 54 else {
                return Unmanaged.passUnretained(event)
            }

            let flags = event.flags
            if flags.contains(.maskCommand) && !manager.isPressed {
                manager.isPressed = true
                let mode: ProcessingMode
                if flags.contains(.maskAlternate) {
                    mode = .translate
                } else if flags.contains(.maskShift) {
                    mode = .raw
                } else {
                    mode = .cleanup
                }
                manager.onPress?(mode)
            } else if !flags.contains(.maskCommand) && manager.isPressed {
                manager.isPressed = false
                manager.onRelease?()
            }
            return Unmanaged.passUnretained(event)
        }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
}
