# Speech and translation support

Voice Engine turns speech into text. Apple Translation turns that text into the
Show as language. A translation pack does not add speech recognition support.

The Voice Engine page lists each model's **Supported languages** and **Ready on
this Mac** languages. The second list includes only supported languages whose
speech assets are installed. The status beneath these lists describes the current
I speak language. Downloading a model does not select it automatically.

| Engine | Language support comes from | What needs installing |
| --- | --- | --- |
| Apple Speech (older) | Each locale's `supportsOnDeviceRecognition`, after Speech Recognition permission | Built-in recognizer; offline availability varies by Mac |
| Apple Speech Analyzer | `SpeechTranscriber.supportedLocales` on this Mac | Language assets from `installedLocales`; use Download speech language when missing |
| Whisper | Product language routes in `VoiceEngineLanguageCatalog` | The chosen model download covers its listed languages |
| Parakeet | Product routes currently expose English only | The chosen model download |
| Cohere | Product language routes; Thai is excluded | The chosen model download |
| Nemotron | Product language routes; Thai remains experimental | The chosen model download |

These are the languages this app exposes, not a promise that every language an
upstream model supports has been integrated. Models disabled by product/platform
availability do not appear in the picker.

I speak offers confirmed speech languages for the selected engine. In translation
mode it also requires a supported forward translation pair. Show as offers
confirmed Apple Translation pairs. A supported pair needing a download remains
available; unsupported or unverified pairs stay out of the menus while metadata
is checked. Existing selections remain visible as labels so a saved incompatible
configuration can be explained rather than silently changed. Listen stays blocked
until speech support and required speech assets are confirmed.

Language Packs hides unsupported pairs with the current I speak language and
marks unconfirmed metadata as checking.
Download requests use the same direction that was checked. Pack-only support and
Apple Intelligence coverage are displayed separately.

Either way appears only in translation mode for two distinct languages, with
Whisper Small installed and Apple Translation ready in both directions. Enabling
it selects Whisper Small. Disabling it keeps that engine selected; changing back
to Apple Speech could make languages such as Thai unavailable. If a new pair
cannot use Either way, setup turns it off before another Listen starts.

For Thai, an installed Apple translation pack is insufficient. The older Apple
recognizer must report offline Thai recognition, or Analyzer must report Thai
support and installed Thai speech assets. Otherwise choose a Whisper model that
lists Thai. Support is checked without recording audio or downloading assets.

Implementation: `VoiceEngineLanguageReadiness` separates support from downloaded
assets, `LanguageChoicePolicy` supplies shared menus, and
`EitherWayAvailability` requires both directions. Regression coverage lives in
`AppleSpeechLocaleTests.swift`; UI smoke coverage verifies the language lists
without starting audio. Running those UI tests requires macOS automation access;
the latest automated verification did not establish a successful UI smoke run.

## Capability indicators and unavailable controls

Setup, Speak & Type, and the Theater language menus share the same status labels:
Ready, Speech download needed, Translation download needed, Checking availability,
Speech permission needed, or Not supported. The selected language also carries an
icon and an accessibility value describing its status. Unsupported choices remain
hidden, while an incompatible saved selection can still explain why it cannot run.
The language card always shows the selected translation direction and its state.

Language Packs labels the exact source → target direction for every row. Unknown
metadata is a checking state, never permission to offer a download. Check again
retries metadata without starting a download. Download actions are guarded against
stale rows after the pair changes.

Speak captions is shown off and disabled when the session uses the same language,
a required playback voice is missing, or the selected output device is disconnected.
The explanation identifies what to change. Either way playback requires voices for
both directions. Output choices update when audio hardware changes. The saved
playback preference is retained and becomes effective again when the configuration
is usable.

Automatic thermal and silence fallbacks require confirmed speech readiness for the
spoken language. They cannot choose an Apple engine merely because it is built in,
and they do not change a working Either way session to a one-language recognizer.
Starting Listen also rejects readiness results if the chosen model changes while
permission or translation checks are still in progress.

The readiness checklist treats unknown translation metadata as unconfirmed, not
ready, and gives unsupported pairs an explanation rather than download advice.
Onboarding uses the same speech asset readiness and permission action as Voice
Engine. Explicit refreshes and Listen checks re-read translation metadata, so a
previously cached ready result cannot permanently hide removed assets. Download
completion updates the shared Listen state as well as the Language Packs screen.

The macOS menu-bar quick switches show only languages with ready speech assets
and installed translation support. Every offered language carries a Ready label.
Setup remains the place to choose supported languages that need a download.
