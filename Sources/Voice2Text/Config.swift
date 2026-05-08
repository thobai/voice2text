import Foundation

enum ProcessingMode: String, CaseIterable {
    case raw, cleanup, translate

    var systemPrompt: String? {
        switch self {
        case .raw: return nil
        case .cleanup: return "Fix grammar, punctuation, and filler words. Preserve the original language. Output only the corrected text."
        case .translate: return "Translate the following German text to clean, grammatically correct English. Output only the translation."
        }
    }

    var displayName: String {
        switch self {
        case .raw: return "Raw"
        case .cleanup: return "Cleanup"
        case .translate: return "Translate"
        }
    }
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
