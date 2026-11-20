import Foundation

/// Either way decodes one language per window. Whisper re-reads the last few
/// seconds on every tick, so right after the speaker changes that window holds
/// both people: Whisper names one language and writes the whole window in it.
/// The other person's words vanish, or come back translated into the wrong
/// language as a new line. Once a sentence is on the board its audio has done
/// its job, so it leaves the window and the next speaker is decoded alone.
enum EitherWayWindow {
    /// Cut this far before the saved sentence's end. Whisper's segment ends
    /// are not exact; leaving the last word's tail is harmless (the stitcher
    /// matches it), while cutting late could take the next speaker's first word.
    static let leadSeconds: TimeInterval = 0.2

    /// Where to cut the window after a sentence is saved, on the capture clock.
    /// Nil leaves the window as it is: Either way off, an engine that does not
    /// re-read a trailing window, or a sentence with no speech timing.
    static func cutSeconds(
        eitherWay: Bool,
        rereadsWindow: Bool,
        sentence timing: CaptionSpeechTiming?
    ) -> TimeInterval? {
        guard eitherWay, rereadsWindow, let timing, timing.isValid else { return nil }
        return max(0, timing.end - self.leadSeconds)
    }
}
