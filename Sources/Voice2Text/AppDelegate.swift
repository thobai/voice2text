import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var currentMode: ProcessingMode = .cleanup
    var pipeline: PipelineController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()

        // Prompt for accessibility if not trusted (required for global hotkey)
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }

        let controller = PipelineController()
        controller.delegate = self
        pipeline = controller
        controller.setup()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice2Text")
        }
        statusItem.isVisible = true
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        for mode in ProcessingMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == currentMode ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = ProcessingMode(rawValue: raw) else { return }
        currentMode = mode
        statusItem.menu = buildMenu()
    }
}
