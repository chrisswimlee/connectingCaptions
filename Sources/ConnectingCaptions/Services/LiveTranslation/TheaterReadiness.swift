import AVFoundation
import Foundation

/// First-run and stage-call checks. Listen still gates on engine + pack.
enum TheaterReadiness {
    static let captionsPrintAfterSentence =
        "Each sentence appears when it is ready. What you are saying stays in the bar under the board. Pause and Stop drop a leftover. Listen, then type still types that leftover."

    static let listeningStatus =
        "Listening. Each sentence appears when it is ready."

    static let listeningEmpty =
        "Listening. Each sentence appears when it is ready."

    static let pressListen =
        "Press Listen. Each sentence appears when it is ready."

    static let boardIdle =
        "Press Listen. Each sentence appears when it is ready."

    static let boardAfterFirstCaption =
        "Each sentence appears when it is ready."

    static let boardListening =
        "Listening. The next sentence appears here."

    static let talkPackCarryOver = "These names stay for the next talk until you Remove."

    static let screenShareTitle = "Who sees this"
    static let screenShare =
        "Share the slides window when the room should see captions and the meeting should not. Share the Theater window when the meeting should see the board. Screenshots and a whole-screen share include these captions."
    static let screenShareIncluded = screenShare

    /// Idle Overlay leaves a Tools bar that fades until the pointer comes back.
    static let overlayIdleCoach =
        "Hover the Tools bar at the top for Listen and the other controls. It fades when you move away. Slides stay clickable."

    static let overlayIdleHint =
        "Hover the Tools bar at the top for Listen. It fades when you move away."

    /// Presenter shortcuts are off. The faded bar and the menu bar both reach the tools.
    static let overlayIdleMenuBarHint =
        "Hover the Tools bar at the top for Listen and the other controls. It fades when you move away. The menu bar can also show tools or Listen."

    static let stopHelp =
        "Stops the microphone. A real leftover sentence appears once. Printed lines and talk notes stay."

    static let pauseHelp =
        "Holds the microphone and drops a leftover. Printed lines and talk notes stay. A translation already on its way may still land."

    static let resumeHelp =
        "Starts the microphone again. Printed lines and talk notes stay. A dropped leftover does not come back."

    static let pausedStatus = "Paused."

    static let dictationBusy =
        "The microphone is already in use."

    static let openTheaterHelp =
        "Open Theater. Choose Pop-up or Overlay in Theater Window."

    static let showTheater = "Show Theater"

    static let closeTheater = "Close Theater"

    static let showTheaterHelp =
        "Show Theater. Listen stayed."

    static let closeTheaterHelp =
        "Close Theater."

    static let minimizeHelp =
        "Hides the board. The microphone stays on. Printed lines and talk notes stay."

    static let expandTheaterHelp =
        "Show the caption board"

    static let theaterMinimizedStatus =
        "Theater is minimized."

    static let theaterOpenStatus =
        "Theater is open."

    static let openTheaterAndListen = "Open Theater and Listen"

    static let openTheaterPressListen =
        "Open Theater, press Listen, and say a sentence."

    static let historyEmpty =
        "Open Theater and press Listen. Captions will appear here."

    static let historyFromBoard =
        "The board keeps the latest lines. History keeps the whole talk, including lines that scrolled off."

    static let gettingStartedReady = "Theater is ready"

    static let gettingStartedOpen = "Open Theater"

    static let gettingStartedReadyDetail =
        "A caption appeared. Open Theater anytime from the sidebar."

    static let gettingStartedOpenDetail =
        "Voice Engine sharpens speech into text. Translation Engine is Apple Translation on this Mac. Both use the microphone. Open Theater, pick Voice or Translate, then press Listen."

    static let gettingStartedMicrophone =
        "Theater needs the microphone to hear you."

    static let gettingStartedMicrophoneReady =
        "The microphone is allowed. Voice and Translate both use it."

    static let printedLinesStay =
        "A line already on screen stays. Each sentence appears when it is ready, and what you are saying stays in the bar under the board. Pause and Stop drop a leftover. Listen, then type still types that leftover into the other app. Lines that scroll off stay in History."

    static let clearCaptions =
        "Removes every caption. The microphone stays on. Talk notes stay."

    static let clearCaptionsConfirm =
        "This removes every caption. The microphone stays on. Talk notes stay."

    static let talkPack =
        "Lock names from notes, a PDF, a PowerPoint deck, or a JSON list. They stay on this Mac."

    static let autoExportSession =
        "When Listen stops, save Markdown and VTT in Application Support/connectingCaptions/Session Exports. Times are when each caption was accepted."

    static let paceCue =
        "Behind means keep talking slower. Caught up means the last sentence is on screen."

    static let oneSpeakerCloseMic =
        "Best with one speaker and a close mic. Halls, PA bleed, and Q&A will miss words."

    /// Stage card when Either way is active for the current Whisper pair.
    static let eitherWayCloseMic =
        "Either way: take turns in either language of the pair. Two voices at once will mix. English ↔ Korean is the clearest script pair."

    static let transcriptionCopy =
        "Voice Engine sharpens speech into text. Voice writes that text in the language you speak. Switch to Translate for a supported language."

    static let insertIMECaveat =
        "some keyboards paste it instead of typing each letter"

    static let insertHelp =
        "Types the captions already on the board into the frontmost app, and \(insertIMECaveat). Listen, then type is the shortcut that starts a new Listen."

    static let typeIntoAppLocked =
        "Listen, then type unlocks after your first Theater caption. Type the board stays on the Theater window."

    static let speakAndTypeSubtitle =
        "Speak in one language. A bar shows the line, then types it into the app you started in."

    static let typeIntoAppBody =
        "Click into another app, then press the shortcut. The bar shows the line and leaves the keyboard in that app."

    static let typeIntoAppShortcutDetail =
        "Starts a new Listen and types what you say next. A bar shows the line. It does not type the board."

    static let typeIntoAppNeedsAccessibility =
        "This shortcut is saved, but macOS is blocking it. Allow Accessibility, click into another app, then press it."

    /// Type into app is off because every board line was already typed.
    static let insertAlreadyTyped = "Already typed. Copy still has the board."

    static let undoLastCaption =
        "Remove the last printed line. Off-screen captions are already gone. Listen can keep going."

    static let closeWhileListening =
        "Close Theater. The microphone is on, so this asks before it stops. Printed lines come back when you open it again. Talk notes stay."

    static let closeWhileListeningConfirm =
        "This stops the microphone and hides Theater. Printed lines come back when you open it again. Talk notes stay."

    static let closeWhileListeningTitle = "Stop and close Theater?"

    static let closeWhileListeningButton = "Stop and Close"

    static let modeStopsListen =
        "Voice writes what you say. Translate turns each sentence into a supported language with Apple Translation. Switching stops Listen."

    static let spokenLineTitle = "Spoken line"
    static let linePrintTitle = "Line print"
    static let printGapTitle = "Print gap"

    static let spokenLineSameLanguage =
        "Same-language captions already show the spoken line."

    static let spokenLineTranslate =
        "Off is translation only. On the board prints the original language under Show-as when the sentence is ready."

    static let spokenLineSetupNote =
        "Off keeps the translation only. On the board puts the original language under Show-as when the sentence is ready."

    static let captionsOnlyWindow =
        "On the Theater window, hide the tool bar. Move the pointer to show Listen and the other controls."

    static let captionsOnlyPopupOnly =
        "Captions only is for Pop-up. Overlay fades its tool bar until you hover the top. Control-Option-T pins those tools."

    static let overlayPlacementHint =
        "Drag a corner or pick a spot. Keep text here, then slides stay clickable."

    static let captionSize =
        "Caption size — the number shown. A wide window grows this further; a short Overlay bar can shrink it to fit."

    static let captionSizeSpoken =
        "Show-as size — the number shown. Spoken stays about 70% of this. A wide window grows this further; a short Overlay bar can shrink it to fit."

    static let downloadPack = "Download pack"
    static let downloadPackBusy = "Downloading…"
    static let packUnsupported =
        "Apple Translation cannot do this pair. Pick another Show as, or use Voice."

    static let allowMicrophone =
        "Press Listen to allow the microphone."

    static let latencyHUD =
        "mic is Listen to first audio. e2e is speech-start to the printed caption. ASR is the speech engine. MT is Apple Translation."

    static let timedExportHonesty =
        "SRT/VTT times are when the caption committed, not the spoken word."

    static let backingBar =
        "Caption plate puts a dark box behind each Overlay line so the text stays readable on white slides."

    static let talkPackClear =
        "Clear these notes so their names do not carry into the next talk."

    static let presenterHotkeys =
        "Control-Option-H hides or shows Theater, P pauses, K clears, T pins Overlay tools, L starts or stops Listen, R retries a failed translation, = and - change caption size. "
        + "Hover the Overlay Tools bar for the same controls. The menu-bar Theater item changes font, size, plate, and position. Your slides keep focus. A custom Listen shortcut with the same chord wins."

    static let popupStyle =
        "Pop-up opens as a lower third so the slides stay visible. Drag a corner to resize, or choose Fill screen."

    static let transparentStyle =
        "Overlay opens along the bottom and shows the last few lines, like TV captions. Drag it, or pick another spot. "
        + "A Tools label at the top fades until you hover it, and slides stay clickable."

    static let presentationStyle =
        "Choose Pop-up or Overlay. Open Theater to show it; Close Theater to hide it."

    static let alsoHearOtherLanguages =
        "Whisper can auto-detect a question in any setup language. Apple Speech stays on I speak."

    static let speakCaptions =
        "Speak each finished Show-as line on the output you pick. Same-language Listen stays quiet."

    /// Either way copy. The Home toggle enables only when Whisper hears both sides.
    static let dynamicPairing =
        "Speak either language of this pair. Theater shows both. Whisper hears both; Apple Speech stays on I speak."

    static func dynamicPairingHint(isWhisper: Bool) -> String {
        isWhisper
            ? "Either way: speak either language of this pair. Captions stay both."
            : "Either way needs Whisper. This Voice Engine stays on I speak, so a question in Show as is not flipped."
    }

    static var macOSNote: String {
        TheaterAvailability.isSupported
            ? "This Mac can run Theater."
            : TheaterAvailability.unsupportedCopy
    }

    static func voiceEngineLine(asrReady: Bool, modelsOnDisk: Bool) -> String {
        if asrReady || modelsOnDisk {
            return SpokenLanguageResolver.stageEngineSummary()
        }
        return "Download a Voice Engine before Listen. Apple Speech is enough to try."
    }
}

enum TheaterAvailability {
    /// Voice, Translate, and I speak / Show as. Apple Speech Analyzer stays macOS 26+.
    static var isSupported: Bool { true }

    static let unsupportedCopy =
        "Theater is not available on this Mac."
}

/// Listen stays off until the Voice Engine, pack, and microphone permission are green.
/// An undetermined mic still allows Listen so the first press can show the system prompt.
enum TheaterReadyGate {
    struct Snapshot: Equatable {
        var osSupported: Bool
        var voiceEngineReady: Bool
        var languagePackReady: Bool
        var microphoneAllowed: Bool
        var captureAllowed: Bool
        var firstCaptionPrinted: Bool
        var mode: TheaterSessionMode
        /// Why this Voice Engine is not ready, from the live settings.
        var voiceEngineAdvice: String? = nil
        /// This engine hears I speak but is set to another language. One press
        /// of Match I speak fixes it; no other engine is needed.
        var voiceEngineNeedsRealign = false

        var canListen: Bool {
            self.osSupported && self.voiceEngineReady && self.languagePackReady && self.captureAllowed
        }

        var isFullyReady: Bool {
            self.canListen && self.firstCaptionPrinted
        }

        /// The readiness checklist is worth showing: something is still unmet.
        var needsAttention: Bool {
            !self.canListen || !self.microphoneAllowed
        }

        var nextAction: String {
            if !self.osSupported {
                return TheaterAvailability.unsupportedCopy
            }
            if !self.voiceEngineReady {
                return self.voiceEngineAdvice
                    ?? "This Voice Engine does not hear I speak. Open Voice Engine."
            }
            if !self.captureAllowed {
                return MicrophoneAccess.deniedCopy
            }
            if !self.microphoneAllowed {
                return TheaterReadiness.allowMicrophone
            }
            if !self.languagePackReady {
                return "Download the language pack for this pair."
            }
            if !self.firstCaptionPrinted {
                return self.mode == .transcription
                    ? "Press Listen and speak."
                    : "Press Listen and speak."
            }
            return "Ready."
        }
    }

    static func snapshot(
        engineSupportsSource: Bool,
        modelInstalled: Bool,
        sameLanguagePair: Bool,
        pack: TranslationPackAvailability,
        microphone: AVAuthorizationStatus,
        firstCaptionPrinted: Bool,
        mode: TheaterSessionMode = .translation,
        osSupported: Bool = true,
        voiceEngineAdvice: String? = nil,
        voiceEngineNeedsRealign: Bool = false
    ) -> Snapshot {
        let canPromptMic = microphone != .denied && microphone != .restricted
        let packOK = mode == .transcription || sameLanguagePair
            || pack == .installed || pack == .unknown
        return Snapshot(
            osSupported: osSupported,
            voiceEngineReady: engineSupportsSource && modelInstalled,
            languagePackReady: packOK,
            microphoneAllowed: microphone == .authorized,
            captureAllowed: canPromptMic,
            firstCaptionPrinted: firstCaptionPrinted,
            mode: mode,
            voiceEngineAdvice: voiceEngineAdvice,
            voiceEngineNeedsRealign: voiceEngineNeedsRealign
        )
    }

    @MainActor
    static func liveSnapshot(
        pack: TranslationPackAvailability,
        microphone: AVAuthorizationStatus,
        firstCaptionPrinted: Bool
    ) -> Snapshot {
        let settings = SettingsStore.shared
        let source = SpokenLanguageResolver.sourceLanguage(settings: settings)
        let engineSupportsSource = SpokenLanguageResolver.voiceEngineSupportsSource()
        return self.snapshot(
            engineSupportsSource: engineSupportsSource,
            modelInstalled: settings.selectedSpeechModel.isInstalled,
            sameLanguagePair: SpokenLanguageResolver.isSameLanguagePair(),
            pack: pack,
            microphone: microphone,
            firstCaptionPrinted: firstCaptionPrinted,
            mode: settings.theaterSessionMode,
            osSupported: TheaterAvailability.isSupported,
            voiceEngineAdvice: self.voiceEngineAdvice(
                model: settings.selectedSpeechModel,
                source: source,
                heard: SpokenLanguageResolver.heardLanguage(settings: settings)
            ),
            voiceEngineNeedsRealign: !engineSupportsSource
                && VoiceEngineLanguageCatalog.supports(settings.selectedSpeechModel, languageID: source.id)
        )
    }

    /// The older Apple Speech is only the answer when Analyzer is in use and
    /// cannot hear I speak. An engine that can hear it but is set to another
    /// language only needs its language matched, not a different engine.
    static func voiceEngineAdvice(
        model: SettingsStore.SpeechModel,
        source: TranslationLanguage,
        heard: TranslationLanguage?
    ) -> String {
        if VoiceEngineLanguageCatalog.supports(model, languageID: source.id) {
            let heardName = heard?.displayName ?? "another language"
            return "Voice Engine is set to hear \(heardName), not \(source.displayName). Press Match I speak."
        }
        if model == .appleSpeechAnalyzer,
           VoiceEngineLanguageCatalog.supports(.appleSpeech, languageID: source.id)
        {
            return "Apple Speech Analyzer does not hear \(source.displayName). Open Voice Engine and pick the older Apple Speech."
        }
        return "Apple Speech on this Mac does not hear \(source.displayName). Pick another I speak."
    }

    static func microphoneAllowed(_ status: AVAuthorizationStatus) -> Bool {
        status == .authorized
    }
}
