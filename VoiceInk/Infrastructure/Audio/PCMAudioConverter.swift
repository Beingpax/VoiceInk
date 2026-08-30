import AVFoundation
import Foundation

enum PCMAudioConverter {
    static func float32Samples(fromPCM16Data data: Data) -> [Float] {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        var samples = [Float](repeating: 0, count: sampleCount)

        data.withUnsafeBytes { rawBuffer in
            let int16Samples = rawBuffer.bindMemory(to: Int16.self)
            for index in 0..<sampleCount {
                samples[index] = max(-1.0, min(Float(Int16(littleEndian: int16Samples[index])) / 32767.0, 1.0))
            }
        }

        return samples
    }

    static func pcmBuffer(fromPCM16Data data: Data) -> AVAudioPCMBuffer? {
        let samples = float32Samples(fromPCM16Data: data)
        guard !samples.isEmpty,
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000.0,
                channels: 1,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
            ),
            let channel = buffer.floatChannelData?[0]
        else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return }
            channel.update(from: baseAddress, count: samples.count)
        }

        return buffer
    }
}
