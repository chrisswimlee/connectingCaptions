//
//  ASRService+EitherWay.swift
//  fluid
//
//  Either way: a sentence already on the board leaves the window Whisper re-reads.
//

import Foundation

extension ASRService {
    /// True when the engine re-decodes a trailing window of recent audio.
    var rereadsTrailingWindow: Bool {
        self.transcriptionProvider.streamingPreviewMode == .trailingWindow
    }

    /// Drops audio heard before `seconds` on the capture clock, so the next
    /// tick decodes only what came after the saved sentence.
    func releaseSavedSpeech(before seconds: TimeInterval) {
        let dropped = self.audioBuffer.dropSamples(beforeCaptureSeconds: seconds)
        guard dropped > 0 else { return }
        DebugLogger.shared.debug(
            "Either way: dropped \(dropped) samples of saved speech before \(String(format: "%.2f", seconds))s",
            source: "ASRService"
        )
    }
}
