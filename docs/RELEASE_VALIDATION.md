# Validate a release

Run from the repository root on an Apple Silicon Mac with Xcode:

```sh
sh scripts/validate-release.sh --output release-evidence
```

The runner saves individual logs, an XCTest result bundle, a JSON summary, and
`manual-checks.template.json`. It checks both code and the generated interface
catalog. `--ui` also runs the UI smoke test in an interactive desktop session;
that smoke opens Theater but does not start the microphone. Automatic success
does not set `releaseReady` until real quality and manual evidence also pass.
Automatic checks include a Release build and `build.sh verify-bundle`, which
repairs the embedded Whisper framework's layout, re-signs the local build ad-hoc,
and checks the assembled app with strict deep signature verification. Developer ID
signing and notarization still need the signed installer checks below. Finish
editing before running validation: changes to release inputs during a run fail
the automatic result. The fingerprint covers app sources, tests, build and
validation scripts, dependency pins, shared build settings, and CI workflows.
Local evidence is gitignored because it may contain names and transcripts.
XCTest and the UI smoke use temporary Application Support and log directories,
an isolated preferences suite and the in-memory keychain backend. The UI smoke's
test-mode environment flag is recognized only in Debug builds.

## Measure a real talk

1. Record a close-mic talk of at least 12 captions. Include an opening pause,
   two sentences without a pause, a long pause, Pause/Resume, and Stop.
2. From Theater's Board → Export menu, save **Quality review (JSONL)** and **VTT**.
   Keep the recording and exported hypotheses unchanged.
3. Fill each empty `reference` by listening to the recording. For translation
   rows, have a bilingual reviewer write and assess the reference. Do not copy
   the hypothesis into the reference. Old history may also need `languageID`.
4. Add a row with an empty `hypothesis` for every sentence the app missed. A
   missing caption must count as an error rather than disappear from the sample.
5. Score the reviewed file:

```sh
python3 scripts/score-theater-talk.py --gate reference.jsonl \
  --json-output quality.json
```

The gate needs at least 12 reviewed rows for each kind/language group. It reports
recognition and translation separately. WER/CER against a translation reference
measures wording differences; a bilingual reviewer must also check meaning,
names, numbers, negation, and omissions. This arithmetic is not a semantic
translation-quality assessment.

New Apple Speech captions carry recognizer speech timestamps mapped back to
the capture clock, including quiet audio removed before recognition. Zero is
the first accepted microphone packet. Preserve the recording's offset from that
moment when comparing subtitles. Translation wait and the order in which
translations finish do not change these times. Older history, unmatched ASR
corrections, and engines without timestamps retain estimated timing. Mixed
exports can contain both. Inspect the VTT alongside the recording before using
it as a finished video subtitle track.

## Complete the live checks

Copy the generated template to `manual-checks.json`. Record the tester in
`reviewer`. For each check, enter `passed` only after testing this source build,
and put the Mac model, OS, languages, devices, result and evidence location in
`notes`. A changed source fingerprint requires a new review.

| Check | Exercise and expected behavior |
| --- | --- |
| `microphone_and_device_recovery` | Built-in, USB, Bluetooth and an available loopback input; deny/restore permission, unplug the preferred input, and verify fallback without old captions returning. |
| `long_talk_and_pause_resume` | A 20-minute talk, repeated Stop/Listen, silence, Pause/Resume and Clear. No duplicate or lost accepted sentences; inspect timing and memory. |
| `offline_translation` | Install the packs, disconnect networking and caption both directions. Interface language and caption language must be independent. |
| `ime_delivery` | Korean, Japanese and Thai input methods in at least two target apps. Verify the captured target, Unicode text and trailing-fragment behavior. |
| `accessibility_and_layout` | Keyboard-only and VoiceOver, Reduce Motion, Arabic right-to-left chrome, Thai word wrapping, large text and an external display. Check each offered interface language. |
| `signed_update_and_rollback` | In a disposable test account, install a signed/notarized build, update, relaunch and roll back. Confirm the bundle path, signature, settings and history survive. |
| `recorded_demo` | Record the genuine 30-second Listen flow below and note the reviewed media file. |

Repeat the applicable checks on macOS 15 and a current supported macOS release.
Do not update the installed everyday app just to validate the installer.

For this release, include Thai with a speech-ready engine, a missing speech asset,
an unsupported translation direction, and Either way with only one direction
installed. The offered options, readiness indicators, and Listen gate must agree.
Also repeat a full sentence before and after the recognizer's text window advances;
inspect both history rows and subtitle timing. Engines without speech timestamps
can distinguish repetition only when the recognition result retains its separate
occurrences; include that limit in the recorded-talk review.

In Overlay, unlock the text area, move and resize it, then lock it. Verify that
pinning Tools does not allow moving or resizing, and that the saved area survives
closing and reopening Theater. Switch to Pop-up and back, minimize and restore,
and disconnect an external display. Repeat English → Korean with Apple Analyzer,
including a finished recognition update arriving just after a pause; compare the
ASR and MT latency readouts with the recording. Exercise At once, By word, By
letter and Fade with wrapped bilingual captions, Thai/Japanese text and emoji.
Change appearance and print style while text is printing, enable Reduce Motion,
and rapidly Stop/Listen. Captions must remain readable without flashes, partial
final words or old-session cleanup interrupting the new session.

Exercise Clear while a repeated sentence is still translating, and change focus
before stopping Listen, then type. The original captured app must receive the
text, or insertion must fail visibly with copyable text retained. Verify that
diagnostic files do not contain a unique phrase spoken during this test, including
when optional prompt debugging is enabled. Use Clear Diagnostic Logs to remove
logs retained from an older build before testing the new build's logging.

```sh
sh scripts/validate-release.sh --ui --quality reference.jsonl \
  --manual-evidence manual-checks.json --require-ready \
  --output release-evidence
```

`--require-ready` fails if automatic checks, human-reviewed quality, or any live
check is missing. It does not publish a release or upload recordings.

## Record the README demo

Use macOS Screenshot (Shift-Command-5), select only the Theater window region,
enable the microphone, and record an actual session:

1. **0–5 s:** show English → Korean and press Listen.
2. **5–18 s:** speak two short sentences; show the Korean captions arriving with
   the original English underneath. Keep the real pace and latency readout.
3. **18–25 s:** hide the original-language line, then speak one more sentence.
4. **25–30 s:** stop Listen and end the recording.

Review audio, names, translation and screen contents before sharing. Save the
approved clip as `docs/screenshots/theater-demo.mp4` and link it beside the README
screenshots. This file is deliberately absent until a real session is recorded;
a mock animation or a test replay is not evidence of live recognition.
