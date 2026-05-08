import Foundation

enum ProcessingMode: String, CaseIterable {
    case raw, cleanup, translate

    var systemPrompt: String? {
        switch self {
        case .raw: return nil
        case .cleanup: return """
            Clean up the following transcribed speech for clarity and natural flow.
            - Do NOT translate. Keep the text in its original language.
            - Fix grammar, punctuation, and spelling.
            - Remove filler words (um, uh, like, you know), stutters, and repetitions.
            - Handle self-corrections: if the speaker says "sorry, I mean" or "actually" to correct themselves, keep only the corrected version.
            - Write numbers as numerals (e.g., five → 5).
            - Preserve the original meaning, tone, and intent.
            - Output only the cleaned text, nothing else.
            """
        case .translate: return "Translate the following German text to clean, grammatically correct English. Output only the translation."
        }
    }

    var defaultLanguage: String? {
        switch self {
        case .raw: return nil          // auto-detect
        case .cleanup: return "en"     // assume English
        case .translate: return "de"   // assume German input
        }
    }

    /// Returns the configured language for this mode (user override or default)
    var language: String? {
        let key = "language_\(rawValue)"
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored == "auto" ? nil : stored
        }
        return defaultLanguage
    }

    var displayName: String {
        switch self {
        case .raw: return "Raw"
        case .cleanup: return "Cleanup"
        case .translate: return "Translate"
        }
    }

    static let supportedLanguages: [(code: String, name: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("de", "German"),
        ("fr", "French"),
        ("es", "Spanish"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("ja", "Japanese"),
        ("zh", "Chinese"),
        ("ko", "Korean"),
        ("ru", "Russian"),
    ]
}

enum Config {
    static let whisperModel = "ggml-large-v3-turbo"
    static let whisperModelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!
    static let whisperModelPath: URL = {
        let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/whisper")
        return cache.appendingPathComponent("ggml-large-v3-turbo.bin")
    }()
    static let llmModelID = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
    static let sampleRate: Double = 16000
    static let minRecordingDuration: Double = 0.5
    static let maxLLMTokens = 1024
}
