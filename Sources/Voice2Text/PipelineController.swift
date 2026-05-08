import AppKit

private func log(_ msg: String) {
    let line = "[Voice2Text] \(msg)\n"
    if let data = line.data(using: .utf8) {
        FileHandle.standardError.write(data)
        if let fh = FileHandle(forWritingAtPath: "/tmp/voice2text.log") {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        } else {
            FileManager.default.createFile(atPath: "/tmp/voice2text.log", contents: data)
        }
    }
}

@MainActor
final class PipelineController {
    private let recorder = AudioRecorder()
    private let transcription = TranscriptionService()
    private let llm = LLMService()
    private let overlay = OverlayWindow()
    private let hotkey = HotkeyManager()
    private var isProcessing = false
    private var activeMode: ProcessingMode = .cleanup
    private var modelsReady = false
    weak var delegate: AppDelegate?

    func setup() {
        Task {
            log("setup() starting")

            // Show setup window on first run (models not yet downloaded)
            let needsDownload = !FileManager.default.fileExists(atPath: Config.whisperModelPath.path)
            let setupWindow: SetupWindow? = needsDownload ? SetupWindow() : nil
            if let setupWindow {
                setupWindow.state.step = .downloadingWhisper
                setupWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }

            log("setting up hotkey...")
            hotkey.onPress = { [weak self] mode in
                log("hotkey press: \(mode)")
                DispatchQueue.main.async { self?.handlePress(mode: mode) }
            }
            hotkey.onRelease = { [weak self] in
                log("hotkey release")
                DispatchQueue.main.async { self?.handleRelease() }
            }

            let hotkeyOk = hotkey.setup()
            log("hotkey setup: \(hotkeyOk)")
            guard hotkeyOk else {
                log("hotkey setup FAILED - need accessibility permission")
                overlay.show(state: .error("Grant Accessibility, then restart"))
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                overlay.hide()
                return
            }

            do {
                log("ensuring whisper model...")
                if let setupWindow { setupWindow.state.step = .downloadingWhisper }
                else { overlay.show(state: .downloading) }
                try await transcription.ensureModel()
                log("whisper model ready")

                log("ensuring LLM model...")
                if let setupWindow { setupWindow.state.step = .downloadingLLM }
                try await llm.ensureModel()
                log("LLM model ready")

                // Warm up whisper (pre-compile Metal shaders)
                log("warming up whisper...")
                if let setupWindow { setupWindow.state.step = .warmingUp }
                let silence = [Float](repeating: 0, count: 16000) // 1s of silence
                _ = try? await transcription.transcribe(audio: silence, language: "en")
                log("warm-up done")

                if let setupWindow {
                    setupWindow.state.step = .done
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    setupWindow.close()
                } else {
                    overlay.hide()
                }
                modelsReady = true
                log("ready!")
            } catch {
                log("download error: \(error)")
                setupWindow?.close()
                overlay.show(state: .error("Download failed"))
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                overlay.hide()
            }
        }
    }

    private func handlePress(mode: ProcessingMode) {
        log("handlePress called, isProcessing=\(isProcessing), modelsReady=\(modelsReady)")
        guard !isProcessing else { log("already processing, ignoring"); return }
        guard modelsReady else {
            log("models not ready, ignoring")
            return
        }
        isProcessing = true
        activeMode = mode
        do {
            log("starting recorder...")
            try recorder.start()
            log("recording started, showing overlay")
            overlay.show(state: .recording)
            log("recording started OK")
        } catch {
            log("mic error: \(error)")
            overlay.show(state: .error("Mic error"))
            isProcessing = false
        }
    }

    private func handleRelease() {
        guard isProcessing else { return }
        let audio = recorder.stop()
        log("recording stopped, samples: \(audio.count)")
        let minSamples = Int(Config.minRecordingDuration * Config.sampleRate)
        guard audio.count >= minSamples else {
            log("too short, discarding")
            overlay.hide()
            isProcessing = false
            return
        }
        let mode = activeMode
        Task { @MainActor in
            await runPipeline(audio: audio, mode: mode)
        }
    }

    private func runPipeline(audio: [Float], mode: ProcessingMode) async {
        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            overlay.show(state: .transcribing)
            log("transcribing \(audio.count) samples...")
            var text = try await transcription.transcribe(audio: audio, language: mode.language)
            let t1 = CFAbsoluteTimeGetCurrent()
            log("transcribed in \(String(format: "%.1f", t1-t0))s: \(text.prefix(80))")
            if mode != .raw {
                overlay.show(state: .processing)
                log("processing with LLM...")
                text = try await llm.process(text: text, mode: mode)
                let t2 = CFAbsoluteTimeGetCurrent()
                log("LLM done in \(String(format: "%.1f", t2-t1))s: \(text.prefix(80))")
            }
            paste(text: text)
            overlay.show(state: .done)
            log("total pipeline: \(String(format: "%.1f", CFAbsoluteTimeGetCurrent()-t0))s")
        } catch {
            log("pipeline error: \(error)")
            overlay.show(state: .error(error.localizedDescription))
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            overlay.hide()
        }
        isProcessing = false
    }

    private func paste(text: String) {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)

        let vDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pb.clearContents()
            if let previous { pb.setString(previous, forType: .string) }
        }
    }
}
