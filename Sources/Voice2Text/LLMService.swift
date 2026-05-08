import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

final class LLMService {
    private var modelContainer: ModelContainer?

    func ensureModel() async throws {
        guard modelContainer == nil else { return }
        let configuration = ModelConfiguration(id: Config.llmModelID)
        modelContainer = try await #huggingFaceLoadModelContainer(configuration: configuration)
    }

    func process(text: String, mode: ProcessingMode) async throws -> String {
        guard mode != .raw, let systemPrompt = mode.systemPrompt else {
            return text
        }
        try await ensureModel()
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": text]
        ]
        let result = try await modelContainer!.perform { context in
            let input = try await context.processor.prepare(input: .init(messages: messages))
            return try MLXLMCommon.generate(
                input: input,
                parameters: .init(temperature: 0.0),
                context: context
            ) { tokens in
                tokens.count >= Config.maxLLMTokens ? .stop : .more
            }
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
