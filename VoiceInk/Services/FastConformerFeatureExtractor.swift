import Foundation
import Accelerate

struct FastConformerFeatureExtractor {
    var featureDimension: Int { melCount }
    private let sampleRate: Int = 16_000
    private let frameLength: Int = 400
    private let hopLength: Int = 160
    private let fftSize: Int = 512
    private let melCount: Int = 80
    private let epsilon: Float = 1e-6

    private let window: [Float]
    private let melFilters: [[MelWeight]]
    private let dft: vDSP.DiscreteFourierTransform<Float>?
    private let zeroImagInput: [Float]

    init() {
        self.window = vDSP.window(ofType: Float.self,
                                  usingSequence: .hanningDenormalized,
                                  count: frameLength,
                                  isHalfWindow: false)
        self.melFilters = FastConformerFeatureExtractor.buildMelFilterbank(sampleRate: sampleRate,
                                                                           fftSize: fftSize,
                                                                           melCount: melCount)
        self.zeroImagInput = [Float](repeating: 0, count: fftSize)
        self.dft = try? vDSP.DiscreteFourierTransform<Float>(count: fftSize,
                                                             direction: .forward,
                                                             transformType: .complexComplex,
                                                             ofType: Float.self)
    }

    func extract(samples: [Float]) -> [[Float]] {
        guard samples.count >= frameLength, let dft = dft else { return [] }

        let frameCount = (samples.count - frameLength) / hopLength + 1
        var features: [[Float]] = []
        features.reserveCapacity(frameCount)

        var paddedFrame = [Float](repeating: 0, count: fftSize)
        var real = [Float](repeating: 0, count: fftSize)
        var imag = [Float](repeating: 0, count: fftSize)
        var spectrum = [Float](repeating: 0, count: fftSize / 2)
        var windowed = [Float](repeating: 0, count: frameLength)

        samples.withUnsafeBufferPointer { buffer in
            for frameIndex in 0..<frameCount {
                let start = frameIndex * hopLength
                let end = start + frameLength
                if end > buffer.count { break }

                windowed.withUnsafeMutableBufferPointer { destination in
                    guard let dest = destination.baseAddress else { return }
                    dest.assign(from: buffer.baseAddress!.advanced(by: start), count: frameLength)
                }

                vDSP.multiply(windowed, window, result: &windowed)

                paddedFrame.resetToZero()
                paddedFrame.replaceSubrange(0..<frameLength, with: windowed)

                dft.transform(inputReal: paddedFrame,
                              inputImaginary: zeroImagInput,
                              outputReal: &real,
                              outputImaginary: &imag)

                for bin in 0..<spectrum.count {
                    let realValue = real[bin]
                    let imagValue = imag[bin]
                    spectrum[bin] = realValue * realValue + imagValue * imagValue
                }

                var melBins = [Float](repeating: 0, count: melCount)
                for (melIndex, weights) in melFilters.enumerated() {
                    var energy: Float = 0
                    for weight in weights {
                        if weight.index < spectrum.count {
                            energy += spectrum[weight.index] * weight.weight
                        }
                    }
                    melBins[melIndex] = logf(max(energy, epsilon))
                }
                features.append(melBins)
            }
        }

        guard !features.isEmpty else { return [] }

        // Apply per-feature mean normalization
        var columnMeans = [Float](repeating: 0, count: melCount)
        for frame in features {
            for bin in 0..<melCount {
                columnMeans[bin] += frame[bin]
            }
        }

        let featureCount = Float(features.count)
        if featureCount > 0 {
            for bin in 0..<melCount {
                columnMeans[bin] /= featureCount
            }
        }

        for index in 0..<features.count {
            for bin in 0..<melCount {
                features[index][bin] -= columnMeans[bin]
            }
        }

        return features
    }

    private static func buildMelFilterbank(sampleRate: Int, fftSize: Int, melCount: Int) -> [[MelWeight]] {
        let nyquist = Float(sampleRate / 2)
        let minMel: Float = 0
        let maxMel = hzToMel(nyquist)
        let melPoints = (0..<(melCount + 2)).map { index -> Float in
            let fraction = Float(index) / Float(melCount + 1)
            return minMel + (maxMel - minMel) * fraction
        }
        let hzPoints = melPoints.map { melToHz($0) }
        let fftBins = hzPoints.map { Int(floor(Float(fftSize) * $0 / Float(sampleRate))) }

        var filters: [[MelWeight]] = Array(repeating: [], count: melCount)

        for melIndex in 0..<melCount {
            let left = max(fftBins[melIndex], 0)
            let center = max(fftBins[melIndex + 1], 1)
            let right = min(fftBins[melIndex + 2], fftSize / 2)

            var weights: [MelWeight] = []
            if center - left > 0 {
                for bin in left..<center {
                    let weight = Float(bin - left) / Float(max(center - left, 1))
                    weights.append(MelWeight(index: bin, weight: weight))
                }
            }
            if right - center > 0 {
                for bin in center..<right {
                    let weight = Float(right - bin) / Float(max(right - center, 1))
                    weights.append(MelWeight(index: bin, weight: weight))
                }
            }
            filters[melIndex] = weights
        }

        return filters
    }

    private static func hzToMel(_ hz: Float) -> Float {
        2595 * log10(1 + hz / 700)
    }

    private static func melToHz(_ mel: Float) -> Float {
        700 * (pow(10, mel / 2595) - 1)
    }

    private struct MelWeight {
        let index: Int
        let weight: Float
    }
}

private extension Array where Element == Float {
    mutating func resetToZero() {
        guard !isEmpty else { return }
        withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress?.initialize(repeating: 0, count: buffer.count)
        }
    }
}
