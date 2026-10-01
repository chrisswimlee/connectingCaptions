import Foundation

/// Quiet stretches Whisper and Parakeet will caption even though nobody spoke.
/// A long pause stays in the 30-second ring for History. The decode copy drops
/// it, and keeps a short pad of the real room tone so the last phoneme is not
/// cut off. Zeros are worse than room tone: they are the usual hallucination cue.
nonisolated enum PauseIntervalAudio {
    static let defaultSampleRate = 16_000
    /// Same 20 ms frame as the short-silence assessment.
    static let frameSamples = 320
    /// Shorter than a word. An isolated pop in a pause is not speech.
    static let ignoredBurstSeconds: TimeInterval = 0.08
    static let leadingPauseSeconds: TimeInterval = 0.50
    static let leadingPadSeconds: TimeInterval = 0.10
    static let trailingPauseSeconds: TimeInterval = 0.30
    static let trailingPadSeconds: TimeInterval = 0.20
    /// A breath stays. A gap long enough to invent a sentence does not.
    static let internalPauseSeconds: TimeInterval = 1.0
    static let internalPadSeconds: TimeInterval = 0.50

    struct Prepared: Equatable {
        var samples: [Float]
        var isPauseOnly: Bool
    }

    static func preparingForDecode(
        _ samples: [Float],
        floorRMS: Float?,
        sampleRate: Int = defaultSampleRate,
        minimumSamples: Int = 0
    ) -> Prepared {
        guard samples.isEmpty == false, sampleRate > 0 else {
            return Prepared(samples: [], isPauseOnly: true)
        }
        let runs = self.collapsedRuns(samples, floorRMS: floorRMS, sampleRate: sampleRate)
        guard runs.contains(where: { $0.voiced }) else {
            return Prepared(samples: [], isPauseOnly: true)
        }

        var spans = self.keptSpans(runs, sampleCount: samples.count, sampleRate: sampleRate)
        guard spans.isEmpty == false else {
            return Prepared(samples: [], isPauseOnly: true)
        }
        let target = min(samples.count, max(minimumSamples, 0))
        self.borrowQuietAudio(into: &spans, sampleCount: samples.count, target: target)

        var output: [Float] = []
        output.reserveCapacity(spans.reduce(0) { $0 + ($1.upper - $1.lower) })
        for span in spans where span.upper > span.lower {
            output.append(contentsOf: samples[span.lower..<span.upper])
        }
        if output.isEmpty {
            return Prepared(samples: [], isPauseOnly: true)
        }
        return Prepared(samples: output, isPauseOnly: false)
    }

    /// A trailing-window engine re-reads its window, so a pause can be left
    /// out after the model has warmed up. A streaming engine appends this
    /// array and records the full sample count as its cursor. A shortened
    /// copy, including the first second before the ring drops audio, would
    /// point that cursor at the wrong place.
    static func samplesForDecode(
        chunk: [Float],
        prepared: Prepared,
        keepsSampleCursor: Bool,
        warmUpTick: Bool
    ) -> [Float] {
        if warmUpTick || keepsSampleCursor {
            return chunk
        }
        return prepared.samples
    }

    private struct Run {
        var voiced: Bool
        var lower: Int
        var upper: Int
    }

    private struct Span {
        var lower: Int
        var upper: Int
    }

    private static func collapsedRuns(
        _ samples: [Float],
        floorRMS: Float?,
        sampleRate: Int
    ) -> [Run] {
        var runs: [Run] = []
        var index = 0
        while index < samples.count {
            let end = min(index + self.frameSamples, samples.count)
            let voiced = self.frameIsVoiced(samples[index..<end], floorRMS: floorRMS)
            if let last = runs.indices.last, runs[last].voiced == voiced {
                runs[last].upper = end
            } else {
                runs.append(Run(voiced: voiced, lower: index, upper: end))
            }
            index = end
        }

        let burstSamples = self.sampleCount(self.ignoredBurstSeconds, sampleRate: sampleRate)
        for index in runs.indices where runs[index].voiced && (runs[index].upper - runs[index].lower) < burstSamples {
            runs[index].voiced = false
        }

        var merged: [Run] = []
        for run in runs {
            if let last = merged.indices.last, merged[last].voiced == run.voiced {
                merged[last].upper = run.upper
            } else {
                merged.append(run)
            }
        }
        return merged
    }

    private static func frameIsVoiced(_ samples: ArraySlice<Float>, floorRMS: Float?) -> Bool {
        guard samples.isEmpty == false else { return false }
        var squareSum = 0.0
        for sample in samples {
            guard sample.isFinite else { return false }
            squareSum += Double(sample) * Double(sample)
        }
        let rms = Float(sqrt(squareSum / Double(samples.count)))
        return SpeechEnergyGate.isAboveSpeech(rms: rms, floorRMS: floorRMS)
    }

    private static func keptSpans(_ runs: [Run], sampleCount: Int, sampleRate: Int) -> [Span] {
        var spans: [Span] = []
        for run in runs {
            let span = self.span(for: run, sampleCount: sampleCount, sampleRate: sampleRate)
            guard span.upper > span.lower else { continue }
            if let last = spans.indices.last, spans[last].upper >= span.lower {
                spans[last].upper = max(spans[last].upper, span.upper)
            } else {
                spans.append(span)
            }
        }
        return spans
    }

    private static func span(for run: Run, sampleCount: Int, sampleRate: Int) -> Span {
        if run.voiced {
            return Span(lower: run.lower, upper: run.upper)
        }
        let duration = Double(run.upper - run.lower) / Double(sampleRate)
        let isLeading = run.lower == 0
        let isTrailing = run.upper == sampleCount
        if isLeading, isTrailing {
            return Span(lower: run.lower, upper: run.lower)
        }
        if isLeading, duration > self.leadingPauseSeconds {
            let pad = self.sampleCount(self.leadingPadSeconds, sampleRate: sampleRate)
            return Span(lower: max(run.lower, run.upper - pad), upper: run.upper)
        }
        if isTrailing, duration > self.trailingPauseSeconds {
            let pad = self.sampleCount(self.trailingPadSeconds, sampleRate: sampleRate)
            return Span(lower: run.lower, upper: min(run.upper, run.lower + pad))
        }
        if isLeading == false, isTrailing == false, duration > self.internalPauseSeconds {
            let pad = self.sampleCount(self.internalPadSeconds, sampleRate: sampleRate)
            return Span(lower: run.lower, upper: min(run.upper, run.lower + pad))
        }
        return Span(lower: run.lower, upper: run.upper)
    }

    /// Whisper refuses a buffer under a second. Borrow the quiet audio next to
    /// the speech until that floor, and stop there, so the rest of the pause
    /// stays out of the decode.
    private static func borrowQuietAudio(into spans: inout [Span], sampleCount: Int, target: Int) {
        guard target > 0, spans.isEmpty == false else { return }
        var count = spans.reduce(0) { $0 + ($1.upper - $1.lower) }
        while count < target {
            var grew = false
            for index in spans.indices {
                let limit = index + 1 < spans.count ? spans[index + 1].lower : sampleCount
                guard spans[index].upper < limit else { continue }
                let take = min(limit - spans[index].upper, target - count)
                spans[index].upper += take
                count += take
                grew = true
                if count >= target { return }
            }
            if spans[0].lower > 0 {
                let take = min(spans[0].lower, target - count)
                spans[0].lower -= take
                count += take
                grew = true
            }
            if grew == false { return }
        }
    }

    private static func sampleCount(_ seconds: TimeInterval, sampleRate: Int) -> Int {
        let value = (seconds * Double(sampleRate)).rounded()
        guard value.isFinite, value > 0 else { return 0 }
        return Int(value)
    }
}
