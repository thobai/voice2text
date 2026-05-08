import AppKit
import AVFoundation

enum Permissions {
    static func checkAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func checkMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            let alert = NSAlert()
            alert.messageText = "Microphone Access Required"
            alert.informativeText = "Please enable microphone access in System Settings > Privacy & Security > Microphone."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return false
        }
    }

    static func checkAll() async -> Bool {
        let accessibility = checkAccessibility()
        let microphone = await checkMicrophone()
        return accessibility && microphone
    }
}
