import Accelerate
import Foundation

/// Causal low-pass before reducing the hardware rate to 16 kHz. A 7 kHz
/// cutoff leaves a transition band below the output Nyquist frequency.
/// History is retained across packets; delay is about 1.3 ms at 48 kHz.
struct SpeechAntiAliasFilter {
    private let coefficients: [Float]
    private var history: [Float]

    init(sourceSampleRate: Double) {
        let length = Int(ceil(sourceSampleRate / 48_000)) * 128 + 1
        let center = Double(length - 1) / 2
        let cutoff = 7_000 / sourceSampleRate
        let raw = (0..<length).map { index -> Float in
            let distance = Double(index) - center
            let sinc = distance == 0 ? 2 * cutoff : sin(2 * .pi * cutoff * distance) / (.pi * distance)
            let phase = 2 * Double.pi * Double(index) / Double(length - 1)
            let window = 0.42 - 0.5 * cos(phase) + 0.08 * cos(2 * phase)
            return Float(sinc * window)
        }
        let sum = raw.reduce(0, +)
        self.coefficients = raw.map { $0 / sum }
        self.history = Array(repeating: 0, count: length - 1)
    }

    mutating func process(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let input = self.history + samples
        var output = [Float](repeating: 0, count: samples.count)
        // The symmetric FIR coefficients allow forward traversal for vDSP_conv.
        vDSP_conv(input, 1, self.coefficients, 1, &output, 1,
                  vDSP_Length(samples.count), vDSP_Length(self.coefficients.count))
        self.history = Array(input.suffix(self.coefficients.count - 1))
        return output
    }
}
