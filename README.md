# Voice2Text

A native macOS menu-bar app for push-to-talk voice transcription. Hold Right Command to record, release to transcribe and paste into the active application.

- **Whisper.cpp** (large-v3-turbo) with Metal acceleration + flash attention
- **Local LLM** (Qwen2.5-1.5B-Instruct-4bit via MLX) for text cleanup and translation
- **Zero cloud dependencies** — everything runs locally on your Mac

## Install via Homebrew

```bash
brew tap thobai/voice2text
brew install voice2text
```

## Usage

Start the app:
```bash
open $(brew --prefix)/opt/voice2text/Voice2Text.app
```

Or run as a background service:
```bash
brew services start voice2text
```

**Grant Accessibility permission** when prompted (System Settings > Privacy & Security > Accessibility).

### Controls

- **Hold Right Command** — start recording
- **Release Right Command** — transcribe and paste

### Modes

The menu bar icon provides mode switching:
- **Raw** — paste transcription as-is
- **Cleanup** — fix grammar and filler words
- **Translate** — translate German to English

## Build from Source

Requires Xcode 15+ and CMake.

```bash
# Clone
git clone https://github.com/thobai/voice2text.git
cd voice2text

# Build whisper.cpp xcframework
git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git /tmp/whisper.cpp
cd /tmp/whisper.cpp && bash build-xcframework.sh
cp -R build-apple/whisper.xcframework /path/to/voice2text/
cd /path/to/voice2text

# Build
swift build -c release

# Create app bundle
bash scripts/build.sh
```

## Models

Downloaded automatically on first run to:
- Whisper: `~/.cache/whisper/ggml-large-v3-turbo.bin` (~1.5GB)
- LLM: `~/.cache/huggingface/` (~1GB)

## License

MIT
