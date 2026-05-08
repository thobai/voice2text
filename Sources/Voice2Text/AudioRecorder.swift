import AVFoundation

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var buffer: [Float] = []

    func start() throws {
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        // Install tap using hardware format, then convert to 16kHz mono
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: hwFormat, to: targetFormat)!

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] pcmBuffer, _ in
            guard let self else { return }
            let ratio = 16000.0 / hwFormat.sampleRate
            let outputFrames = AVAudioFrameCount(Double(pcmBuffer.frameLength) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrames) else { return }

            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return pcmBuffer
            }
            guard error == nil, let channelData = outputBuffer.floatChannelData else { return }
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
            self.lock.lock()
            self.buffer.append(contentsOf: samples)
            self.lock.unlock()
        }

        engine.prepare()
        try engine.start()
    }

    func stop() -> [Float] {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        lock.lock()
        let samples = buffer
        buffer = []
        lock.unlock()
        return samples
    }
}
