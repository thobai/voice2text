# Plan: Swift Voice2Text Rewrite

## Summary
Rewrite the existing Python push-to-talk voice transcription app as a native Swift macOS menu-bar utility. The app listens for Right Command key, records audio, transcribes via whisper.cpp (SwiftWhisper), optionally processes with a local LLM (mlx-swift-lm / Qwen2.5-1.5B-Instruct-4bit), and pastes the result into the active application. Built entirely with Swift Package Manager for zero-cost Homebrew distribution.

## Clarifications

### Session 2026-05-08
- Q: When model auto-download fails (network timeout, disk full, partial file), what should the app do? → A: Show error in the overlay HUD for 5 seconds, retry on next hotkey press.
- Q: Should models be pre-downloaded at first launch or lazily on first use? → A: Pre-download both models at first launch (show progress overlay, block hotkey until done).
- Q: If the frontmost app doesn't support paste, should the app handle this case? → A: No special handling — paste blindly, matching Python behavior.
- Q: Should the app include a LaunchAgent plist for auto-start at login? → A: Yes, include LaunchAgent plist in the build script output (auto-install with `launchctl load`).
- Q: Should the app apply output sanitization beyond .strip() for malformed LLM responses? → A: No — strip only, matching Python behavior.

## Context
Key findings from the Python source (`~/repo/pyvoice2text/`):

- **Whisper:** Uses `pywhispercpp` with model `large-v3-turbo`, 16kHz mono float32 audio, default parameters, segments joined by space
- **LLM:** Uses `mlx-lm` with `mlx-community/Qwen2.5-1.5B-Instruct-4bit`, chat template with system/user messages, `max_tokens=1024`, greedy decoding, output `.strip()` only
- **Modes:** `raw` (transcribe only), `cleanup` (fix grammar/punctuation), `translate` (German→English)
- **Hotkey:** CGEventTap on `kCGEventFlagsChanged`, keycode `0x36` (Right Cmd), modifier combos select mode
- **UI:** NSPanel-based floating HUD (pill shape, bottom-center, vibrancy) showing Recording/Processing states
- **Output:** Clipboard swap + synthetic Cmd+V + restore original clipboard after 100ms
- **Lifecycle:** LSUIElement menu-bar app, no dock icon

**Dependency decisions:**
- **SwiftWhisper** (`https://github.com/exPHAT/SwiftWhisper.git`) — SPM-compatible whisper.cpp wrapper, supports ggml models
- **mlx-swift-lm** (`https://github.com/ml-explore/mlx-swift-lm`) — Official Apple MLX LLM inference, supports Qwen2.5
- **No hotkey package needed** — CGEvent tap works directly from Swift for modifier-only keys
- **No Xcode project** — pure SPM with `swift build -c release`

## Implementation Details

### Approach
Structure as a macOS AppKit app (NSApplication) launched from an executable target. Use `NSApplication.shared.setActivationPolicy(.accessory)` for LSUIElement behavior (no dock icon). The app runs a CGEvent tap for the hotkey and presents a SwiftUI-hosted NSPanel for the floating HUD. Audio recording uses AVFoundation's `AVAudioEngine` (simpler than `AVCaptureSession` for mic-only). The ML pipeline runs on a background Task.

### Key Artifacts

#### Package.swift Structure
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Voice2Text",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", branch: "master"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.0"),
    ],
    targets: [
        .executableTarget(
            name: "Voice2Text",
            dependencies: [
                "SwiftWhisper",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ]
        ),
    ]
)
```

#### App Entry Point (AppDelegate pattern)
```swift
import AppKit

@main
struct Voice2TextApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // No dock icon
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
```

#### State Machine
```swift
enum AppState {
    case idle
    case downloading
    case recording
    case transcribing
    case processing
    case done
}
```

#### Hotkey Detection (CGEvent Tap)
```swift
func setupEventTap() -> Bool {
    guard let tap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
        callback: eventCallback,
        userInfo: nil
    ) else { return false }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
}
```

#### Mode Selection from Modifier Flags
```swift
func modeFromFlags(_ flags: CGEventFlags) -> ProcessingMode {
    if flags.contains(.maskAlternate) { return .translate }
    if flags.contains(.maskShift) { return .raw }
    return .cleanup
}
```

#### LLM System Prompts
```swift
enum ProcessingMode: String {
    case raw, cleanup, translate
    
    var systemPrompt: String? {
        switch self {
        case .raw: return nil
        case .cleanup: return "Fix grammar, punctuation, and filler words. Preserve the original language. Output only the corrected text."
        case .translate: return "Translate the following German text to clean, grammatically correct English. Output only the translation."
        }
    }
}
```

#### Audio Recording (AVAudioEngine)
```swift
let engine = AVAudioEngine()
var audioBuffer: [Float] = []

func startRecording() {
    let input = engine.inputNode
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
        let ptr = buffer.floatChannelData![0]
        audioBuffer.append(contentsOf: UnsafeBufferPointer(start: ptr, count: Int(buffer.frameLength)))
    }
    try engine.start()
}
```

#### Whisper Transcription
```swift
import SwiftWhisper

func transcribe(audio: [Float]) async throws -> String {
    let whisper = Whisper(fromFileURL: modelURL)
    let segments = try await whisper.transcribe(audioFrames: audio)
    return segments.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
}
```

#### MLX LLM Processing
```swift
import MLXLLM
import MLXLMCommon

func processWithLLM(text: String, mode: ProcessingMode) async throws -> String {
    guard let systemPrompt = mode.systemPrompt else { return text }
    let model = try await loadModel(using: TokenizersLoader(), id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit")
    let session = ChatSession(model)
    // Set system prompt via initial message structure
    let result = try await session.respond(to: text, systemPrompt: systemPrompt)
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}
```

#### Clipboard + Paste
```swift
func pasteText(_ text: String) {
    let pb = NSPasteboard.general
    let old = pb.string(forType: .string)
    pb.clearContents()
    pb.setString(text, forType: .string)
    
    // Synthetic Cmd+V
    let vDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)!
    vDown.flags = .maskCommand
    vDown.post(tap: .cghid)
    let vUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)!
    vUp.flags = .maskCommand
    vUp.post(tap: .cghid)
    
    // Restore after 100ms
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        pb.clearContents()
        if let old { pb.setString(old, forType: .string) }
    }
}
```

## Verification Strategy
- Build with `swift build -c release` — must compile without errors
- Run the binary and verify: menu bar icon appears, no dock icon
- Test accessibility permission prompt when event tap fails
- Test microphone permission prompt on first recording
- Test Right Cmd press/release cycle through all states
- Test each mode (raw, cleanup, translate) end-to-end
- Verify clipboard paste works in a text editor
- Verify floating HUD appears/disappears correctly

## Tasks

### Task 1: SPM Scaffolding & Package.swift
- **Parallel Group:** A
- **Depends On:** —
- **Files:** `Package.swift`, `Sources/Voice2Text/Config.swift`
- **Description:** Create the Swift Package Manager project structure:
  - `Package.swift` with SwiftWhisper and mlx-swift-lm dependencies (see Key Artifacts above)
  - `Sources/Voice2Text/` directory
  - `Config.swift` with constants: whisper model name (`large-v3-turbo`), LLM model ID (`mlx-community/Qwen2.5-1.5B-Instruct-4bit`), sample rate (16000), min recording duration (0.5), and the `ProcessingMode` enum with system prompts
- **Verification:** Run `swift package resolve` — must succeed without errors. Run `swift build` — may fail on missing source files but package resolution must work.

### Task 2: App Entry Point & Menu Bar
- **Parallel Group:** B
- **Depends On:** 1
- **Files:** `Sources/Voice2Text/main.swift`, `Sources/Voice2Text/AppDelegate.swift`
- **Description:** Create the application entry point and AppDelegate:
  - `main.swift`: Initialize NSApplication, set activation policy to `.accessory`, assign delegate, run
  - `AppDelegate.swift`: Create NSStatusItem with SF Symbol `mic.fill`, build a menu with mode selection (Raw/Cleanup/Translate checkmarks) and Quit item. Store the selected default mode. Handle `applicationDidFinishLaunching` to set up the status bar and request permissions.
  - No `@main` attribute — use explicit `main.swift` for SPM compatibility
- **Verification:** `swift build` compiles. Running the binary shows a mic icon in the menu bar with no dock icon. Menu items are clickable.

### Task 3: Permissions Handling
- **Parallel Group:** B
- **Depends On:** 1
- **Files:** `Sources/Voice2Text/Permissions.swift`
- **Description:** Create a permissions module that:
  - Checks accessibility permission with `AXIsProcessTrusted()`. If not trusted, show an alert explaining the need and offer to open System Settings (Privacy > Accessibility). Use `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt` to trigger the system prompt.
  - Checks microphone permission with `AVCaptureDevice.authorizationStatus(for: .audio)`. If not determined, request with `AVCaptureDevice.requestAccess(for: .audio)`. If denied, show alert directing to System Settings.
  - Provide a `checkAllPermissions() -> Bool` function called at launch.
  - Add an `Info.plist` partial or note that the app bundle's Info.plist needs `NSMicrophoneUsageDescription` (handled in Task 10).
- **Verification:** `swift build` compiles. When run without accessibility permission, the system prompt appears. When run without microphone permission, the request dialog appears.

### Task 4: Hotkey Manager (CGEvent Tap)
- **Parallel Group:** B
- **Depends On:** 1
- **Files:** `Sources/Voice2Text/HotkeyManager.swift`
- **Description:** Implement the global hotkey detection:
  - Create a `HotkeyManager` class that sets up a CGEvent tap for `.flagsChanged` events
  - Filter for keycode 54 (Right Command)
  - On press: determine mode from modifier flags (Option→translate, Shift→raw, none→cleanup), call `onPress(mode:)` callback
  - On release: call `onRelease()` callback
  - Handle tap creation failure gracefully (return false, caller shows permission alert)
  - Use `CFRunLoopGetMain()` for the run loop source
  - Store callbacks as closures set by the AppDelegate
- **Verification:** `swift build` compiles. With accessibility permission granted, pressing Right Cmd triggers the press callback, releasing triggers release. Mode detection works with Shift/Option combos.

### Task 5: Audio Recorder (AVAudioEngine)
- **Parallel Group:** B
- **Depends On:** 1
- **Files:** `Sources/Voice2Text/AudioRecorder.swift`
- **Description:** Implement audio recording using AVAudioEngine:
  - `AudioRecorder` class with `start()` and `stop() -> [Float]` methods
  - Configure input node tap at 16kHz, mono, float32 (use format converter if hardware format differs)
  - Accumulate samples in a `[Float]` buffer (thread-safe with a lock or actor)
  - `stop()` returns the accumulated buffer and resets state
  - Handle the case where the audio engine's input node native format is not 16kHz — install tap with desired format (AVAudioEngine handles conversion automatically when you specify a different format in `installTap`)
- **Verification:** `swift build` compiles. Recording for 2 seconds produces a buffer of ~32000 float samples. Audio data is valid (not all zeros).

### Task 6: Floating HUD Overlay (SwiftUI + NSPanel)
- **Parallel Group:** B
- **Depends On:** 1
- **Files:** `Sources/Voice2Text/OverlayWindow.swift`, `Sources/Voice2Text/OverlayView.swift`
- **Description:** Create the floating status HUD:
  - `OverlayWindow`: Subclass of NSPanel, configured as borderless, non-activating, floating, ignores mouse events, `.hudWindow` style level. Positioned bottom-center of main screen (150×36px area). Uses NSHostingView to host SwiftUI content.
  - `OverlayView`: SwiftUI view showing state-dependent content:
    - `.downloading`: Download icon + "Downloading model..." text
    - `.recording`: Red pulsing circle + "Recording" text
    - `.transcribing`: Spinner + "Transcribing..." text
    - `.processing`: Spinner + "Processing..." text
    - `.done`: Checkmark + "Copied!" text (auto-hides after 1s)
  - Pill-shaped with rounded corners, dark vibrancy background (NSVisualEffectView or `.ultraThinMaterial`)
  - `show(state:)` and `hide()` methods with fade animation
  - Accepts an `AppState` binding or observed object
- **Verification:** `swift build` compiles. Calling `show(state: .recording)` displays the overlay at bottom-center. Calling `hide()` fades it out.

### Task 7: Whisper Transcription Service
- **Parallel Group:** B
- **Depends On:** 1
- **Files:** `Sources/Voice2Text/TranscriptionService.swift`
- **Description:** Implement whisper.cpp transcription via SwiftWhisper:
  - `TranscriptionService` class that loads the whisper model once (lazy initialization)
  - Model path: `~/.cache/whisper/ggml-large-v3-turbo.bin` (configurable via `WHISPER_MODEL_PATH` env var)
  - Auto-download: On first use, if model file is missing, download from HuggingFace (`https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin`) using URLSession. Show download progress in overlay ("⬇️ Downloading model..."). Save to the cache path.
  - `transcribe(audio: [Float]) async throws -> String` method
  - Join segments by space, trim whitespace (matching Python behavior)
  - Handle download failure with a clear error message and retry option
  - On download failure (network error, disk full, partial file): show error message in overlay HUD for 5 seconds (e.g., "❌ Download failed"), delete any partial file, return to idle. Retry automatically on next hotkey press.
- **Verification:** `swift build` compiles. With a valid model file and sample audio, transcription returns non-empty text.

### Task 8: MLX LLM Processing Service
- **Parallel Group:** B
- **Depends On:** 1
- **Files:** `Sources/Voice2Text/LLMService.swift`
- **Description:** Implement LLM text processing via mlx-swift-lm:
  - `LLMService` class that loads the model once (lazy initialization)
  - Model: `mlx-community/Qwen2.5-1.5B-Instruct-4bit` (downloaded from HuggingFace on first use, cached locally by mlx-swift-lm's built-in HuggingFace integration)
  - `process(text: String, mode: ProcessingMode) async throws -> String` method
  - If mode is `.raw`, return text unchanged (short-circuit)
  - Construct chat messages: system prompt from mode + user message with transcribed text
  - Use `ChatSession` or lower-level generate API with max_tokens=1024
  - Strip whitespace from result
  - Offline-first: Set `HF_HUB_OFFLINE=1` in the app's environment after initial model download. The build script / LaunchAgent should also set this. On first launch, if model is not cached, download it (mlx-swift-lm handles this via HuggingFace Hub).
- **Verification:** `swift build` compiles. With model downloaded, processing "hello world" in cleanup mode returns a result. Raw mode returns input unchanged.

### Task 9: Pipeline Orchestrator & Clipboard
- **Parallel Group:** C
- **Depends On:** 2, 3, 4, 5, 6, 7, 8
- **Files:** `Sources/Voice2Text/PipelineController.swift`
- **Description:** Wire everything together in the main pipeline controller:
  - `PipelineController` class (or actor) that owns: `AudioRecorder`, `TranscriptionService`, `LLMService`, `OverlayWindow`, `HotkeyManager`
  - State management: `idle` → `recording` → `transcribing` → `processing` → `done` → `idle`
  - On launch: check if models are cached. If not, show overlay `.downloading` and pre-download both (whisper + LLM) before enabling hotkey. Block hotkey until download completes. On failure, show error in overlay for 5 seconds, retry on next app launch or manual trigger from menu.
  - On hotkey press: guard against re-entry if processing, start recording, show overlay `.recording`
  - On hotkey release: stop recording, check min duration (0.5s at 16kHz = 8000 samples), if too short discard and hide overlay
  - Pipeline (async): transcribe → process with LLM → paste → hide overlay
  - Paste implementation: save clipboard, set text, synthetic Cmd+V (keycode 0x09), restore after 100ms
  - Update overlay state at each pipeline stage
  - Run pipeline on a detached Task, dispatch UI updates to MainActor
  - Connect HotkeyManager callbacks to pipeline methods in AppDelegate
- **Verification:** `swift build -c release` compiles without errors. Full end-to-end test: press Right Cmd, speak, release, verify text appears in a text editor. Test all three modes.

### Task 10: App Bundle & Build Script
- **Parallel Group:** D
- **Depends On:** 9
- **Files:** `scripts/build.sh`, `Resources/Info.plist`, `Resources/com.local.voice2text.plist`
- **Description:** Create the build and packaging infrastructure:
  - `scripts/build.sh`: Builds with `swift build -c release`, creates a `.app` bundle structure (`Voice2Text.app/Contents/MacOS/`, `Contents/Resources/`, `Contents/Info.plist`), copies the binary, ad-hoc signs with `codesign -s - --force --deep`. Also installs the LaunchAgent plist to `~/Library/LaunchAgents/` and loads it with `launchctl load`.
  - `Resources/Info.plist`: Bundle ID `com.local.voice2text`, `LSUIElement=true`, `NSMicrophoneUsageDescription`, `CFBundleExecutable`, minimum system version 14.0, `LSEnvironment` with `HF_HUB_OFFLINE=1`
  - `Resources/com.local.voice2text.plist`: LaunchAgent plist that runs the .app at login, sets `HF_HUB_OFFLINE=1`, logs to `/tmp/voice2text.log`
  - Add a `.gitignore` for `.build/`, `Voice2Text.app/`
- **Verification:** Running `./scripts/build.sh` produces `Voice2Text.app` that launches correctly as a menu-bar app. `codesign -v Voice2Text.app` passes. The app has no dock icon and shows the mic menu bar icon.

## Risk Assessment
- **Risk Level:** Medium-High
- **Key Risks:**
  - **SwiftWhisper API stability:** The package uses `branch: "master"` — API may change. Mitigation: pin to a specific commit if needed.
  - **mlx-swift-lm API:** The `ChatSession` API is relatively new (v3.x). Exact method signatures for system prompts need verification during implementation. Mitigation: fall back to lower-level `generate()` API if needed.
  - **Build times:** mlx-swift-lm pulls in significant dependencies (swift-syntax, transformers). First build will be slow. Not a runtime concern.
  - **First-run download:** Both whisper model (~1.5GB) and LLM model (~1GB) must download on first use. Need clear progress indication and error handling for network failures.
  - **Accessibility permission UX:** Without an .app bundle signed by a Developer ID, macOS may be more restrictive. Ad-hoc signing should work for local use.
  - **AVAudioEngine format conversion:** The input node's native format may not be 16kHz — need to handle resampling correctly.

## Estimated Scope
- Files modified: 0
- Files created: 13
- Tests affected: 0 (no test target in initial scope — can add later)
