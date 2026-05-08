import Foundation
import whisper

class TranscriptionService {
    private var ctx: OpaquePointer?

    func ensureModel() async throws {
        let path = Config.whisperModelPath
        if FileManager.default.fileExists(atPath: path.path) { return }
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let (tempURL, _) = try await URLSession.shared.download(from: Config.whisperModelURL)
        do {
            try FileManager.default.moveItem(at: tempURL, to: path)
        } catch {
            try? FileManager.default.removeItem(at: path)
            throw error
        }
    }

    func transcribe(audio: [Float]) async throws -> String {
        try await ensureModel()

        if ctx == nil {
            var cparams = whisper_context_default_params()
            cparams.flash_attn = true
            ctx = whisper_init_from_file_with_params(Config.whisperModelPath.path, cparams)
            guard ctx != nil else { throw TranscriptionError.modelLoadFailed }
        }

        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { [ctx] in
                guard let ctx else {
                    cont.resume(throwing: TranscriptionError.modelLoadFailed)
                    return
                }
                var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))
                params.print_progress = false
                params.print_timestamps = false

                let result = audio.withUnsafeBufferPointer { buf in
                    whisper_full(ctx, params, buf.baseAddress, Int32(audio.count))
                }

                guard result == 0 else {
                    cont.resume(throwing: TranscriptionError.transcriptionFailed)
                    return
                }

                let nSegments = whisper_full_n_segments(ctx)
                var text = ""
                for i in 0..<nSegments {
                    if let cStr = whisper_full_get_segment_text(ctx, i) {
                        let seg = String(cString: cStr).trimmingCharacters(in: .whitespaces)
                        if !seg.isEmpty {
                            if !text.isEmpty { text += " " }
                            text += seg
                        }
                    }
                }
                cont.resume(returning: text)
            }
        }
    }

    deinit {
        if let ctx { whisper_free(ctx) }
    }
}

enum TranscriptionError: Error {
    case modelLoadFailed, transcriptionFailed
}
