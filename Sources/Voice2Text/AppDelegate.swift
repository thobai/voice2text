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
            // Poll until granted
            pollForAccessibility()
        } else {
            startPipeline()
        }
    }

    private func pollForAccessibility() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                DispatchQueue.main.async {
                    self?.startPipeline()
                }
            }
        }
    }

    @MainActor private func startPipeline() {
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

            let shortcut: String
            switch mode {
            case .raw: shortcut = "⇧ Right ⌘"
            case .cleanup: shortcut = "Right ⌘"
            case .translate: shortcut = "⌥ Right ⌘"
            }

            let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 22))

            let titleLabel = NSTextField(labelWithString: mode.displayName)
            titleLabel.font = NSFont.menuFont(ofSize: 14)
            titleLabel.frame = NSRect(x: 20, y: 2, width: 100, height: 18)
            view.addSubview(titleLabel)

            let shortcutLabel = NSTextField(labelWithString: shortcut)
            shortcutLabel.font = NSFont.menuFont(ofSize: 12)
            shortcutLabel.textColor = .secondaryLabelColor
            shortcutLabel.alignment = .right
            shortcutLabel.frame = NSRect(x: 110, y: 2, width: 100, height: 18)
            view.addSubview(shortcutLabel)

            item.view = view
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Language settings submenu
        let langItem = NSMenuItem(title: "Languages", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for mode in ProcessingMode.allCases {
            let modeItem = NSMenuItem(title: mode.displayName, action: nil, keyEquivalent: "")
            let modeSubmenu = NSMenu()
            let currentLang = mode.language ?? "auto"
            for (code, name) in ProcessingMode.supportedLanguages {
                let li = NSMenuItem(title: name, action: #selector(selectLanguage(_:)), keyEquivalent: "")
                li.target = self
                li.representedObject = ["mode": mode.rawValue, "lang": code]
                let effectiveCode = code == "auto" ? "auto" : code
                let isSelected = (currentLang == "auto" && code == "auto") || currentLang == code
                li.state = isSelected ? .on : .off
                modeSubmenu.addItem(li)
            }
            modeItem.submenu = modeSubmenu
            langMenu.addItem(modeItem)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let modeRaw = info["mode"],
              let lang = info["lang"] else { return }
        UserDefaults.standard.set(lang, forKey: "language_\(modeRaw)")
        statusItem.menu = buildMenu()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = ProcessingMode(rawValue: raw) else { return }
        currentMode = mode
        statusItem.menu = buildMenu()
    }
}
