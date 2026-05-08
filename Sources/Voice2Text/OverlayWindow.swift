import AppKit
import SwiftUI

class OverlayWindow: NSPanel {
    let overlayState = OverlayState()
    private var hideTimer: Timer?
    private let windowSize = NSSize(width: 165, height: 40)

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 165, height: 40),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        alphaValue = 0
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let rootView = OverlayView(state: overlayState)
            .frame(width: 165, height: 40)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: windowSize)
        contentView = hostingView
    }

    func show(state: AppState) {
        hideTimer?.invalidate()
        overlayState.appState = state

        let screen = NSScreen.main ?? NSScreen.screens.first
        if let screen {
            let x = screen.frame.midX - windowSize.width / 2
            let y = screen.visibleFrame.origin.y + 80
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().alphaValue = 1
        }
        if state == .done {
            hideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                self?.hide()
            }
        }
    }

    func hide() {
        hideTimer?.invalidate()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.overlayState.appState = .idle
        })
    }
}
