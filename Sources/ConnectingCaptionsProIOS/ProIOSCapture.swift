import AVFoundation
import FluidAudio
import Foundation

/// One microphone packet, copied off the audio thread before the engine reuses the buffer.
struct MicPacket: Sendable {
    var samples: [Float]
    var sampleRate: Double

    init?(_ buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        guard frames > 0, buffer.format.sampleRate > 0 else { return nil }
        let channels = Int(buffer.format.channelCount)
        guard channels > 0 else { return nil }
        if let channel = buffer.floatChannelData {
            self.samples = Self.mix(frames: frames, channels: channels) { channelIndex, frame in
                channel[channelIndex][frame]
            }
        } else if let channel = buffer.int16ChannelData {
            self.samples = Self.mix(frames: frames, channels: channels) { channelIndex, frame in
                Float(channel[channelIndex][frame]) / 32768
            }
        } else {
            return nil
        }
        self.sampleRate = buffer.format.sampleRate
    }

    func makeBuffer() -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: self.sampleRate,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(self.samples.count))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(self.samples.count)
        self.samples.withUnsafeBufferPointer { pointer in
            guard let destination = buffer.floatChannelData?[0], let base = pointer.baseAddress else { return }
            destination.update(from: base, count: self.samples.count)
        }
        return buffer
    }

    private static func mix(frames: Int, channels: Int, sample: (Int, Int) -> Float) -> [Float] {
        var mono = [Float](repeating: 0, count: frames)
        let scale = Float(channels)
        for frame in 0 ..< frames {
            var sum: Float = 0
            for channelIndex in 0 ..< channels {
                sum += sample(channelIndex, frame)
            }
            mono[frame] = sum / scale
        }
        return mono
    }
}

/// Built-in microphone. iOS has no Core Audio device graph, so this is the phone's input.
final class ProIOSMicrophone: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let sink = PartialSink()
    var onPacket: (@Sendable (MicPacket) -> Void)?

    static func prepareSession() throws -> AVAudioSession {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        return session
    }

    /// Lists inputs without activating the session. Activating here stops music before Listen.
    static func inputs() throws -> [ProIOSInput] {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        return (session.availableInputs ?? []).map {
            ProIOSInput(uid: $0.uid, name: $0.portName)
        }
    }

    func start(preferredUID: String?) throws {
        let session = try Self.prepareSession()
        if let preferredUID, let input = session.availableInputs?.first(where: { $0.uid == preferredUID }) {
            try session.setPreferredInput(input)
        } else {
            try session.setPreferredInput(nil)
        }
        let input = self.engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [sink] buffer, _ in
            guard let packet = MicPacket(buffer) else { return }
            sink.forward(packet)
        }
        self.sink.handler = self.onPacket
        self.engine.prepare()
        try self.engine.start()
    }

    func stop() {
        self.engine.inputNode.removeTap(onBus: 0)
        self.engine.stop()
        self.sink.handler = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

/// Holds the tap callback without capturing the session in the audio render block.
final class PartialSink: @unchecked Sendable {
    var handler: (@Sendable (MicPacket) -> Void)?

    func forward(_ packet: MicPacket) {
        self.handler?(packet)
    }
}

struct ProIOSInput: Identifiable, Hashable, Sendable {
    var uid: String
    var name: String
    var id: String { self.uid }
}

/// Every streaming FluidVoice engine FluidAudio can run on this phone.
actor ProIOSRecognizer {
    private var variant: StreamingModelVariant
    private var engine: any StreamingAsrEngine
    private var loadedVariant: StreamingModelVariant?
    private let sink = TranscriptSink()

    init(variant: StreamingModelVariant) {
        self.variant = variant
        self.engine = StreamingAsrEngineFactory.create(variant)
    }

    func select(_ variant: StreamingModelVariant) {
        guard variant != self.variant else { return }
        self.variant = variant
        self.engine = StreamingAsrEngineFactory.create(variant)
        self.loadedVariant = nil
    }

    func setHandler(_ handler: @escaping @Sendable (String) -> Void) {
        self.sink.handler = handler
    }

    func prepare() async throws {
        if self.loadedVariant == self.variant {
            try await self.engine.reset()
            return
        }
        try await self.engine.loadModels()
        let sink = self.sink
        await self.engine.setPartialTranscriptCallback { text in
            sink.forward(text)
        }
        self.loadedVariant = self.variant
    }

    func ingest(_ packet: MicPacket) async throws {
        guard let buffer = packet.makeBuffer() else { return }
        try await self.engine.appendAudio(buffer)
        try await self.engine.processBufferedAudio()
        let partial = await self.engine.getPartialTranscript()
        if !partial.isEmpty {
            self.sink.forward(partial)
        }
    }

    func finish() async -> String {
        let text = (try? await self.engine.finish()) ?? ""
        if !text.isEmpty {
            self.sink.forward(text)
        }
        return text
    }
}

final class TranscriptSink: @unchecked Sendable {
    var handler: (@Sendable (String) -> Void)?

    func forward(_ text: String) {
        self.handler?(text)
    }
}
