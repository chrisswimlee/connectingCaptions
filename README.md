# Connecting Captions

<p align="center">
  <img src="docs/screenshots/app-icon.png" width="96" alt="Connecting Captions icon">
</p>

**Each sentence appears when it is ready.**

Connecting Captions is live subtitles for macOS, with translation on the machine. Choose **I speak** and **Show as** from the compatible language choices. Voice Engine shows which languages each model supports and which are ready on this Mac. Translate follows I speak into Show as. The same language needs no translation pack. A sentence appears when it is ready. Best with one speaker and a close mic. It listens through any input device you pick — the built-in microphone, a wired, USB, or line-in mic, a Bluetooth headset in call mode, or a virtual loopback input (BlackHole or Loopback) when you route other audio into it.

![Translate home](docs/screenshots/translate-home.png)

Open **Theater**, set **I speak** and **Show as**, then press **Open Theater** and **Listen**. A new Listen starts with an empty board. Closing Theater hides the window; it does not keep the last talk for the next Listen. A separate shortcut types the current translation into another app. Translation uses Apple’s on-device Translation framework.

![Theater captions](docs/screenshots/theater.png)

By [Chris Swim Lee](https://chrisswimlee.com). Licensed under GPLv3.

[Download](https://github.com/chrisswimlee/connectingCaptions/releases/latest/download/Connecting-Captions.zip) · [Homebrew](https://github.com/chrisswimlee/homebrew-connectingcaptions) · [Product page](https://local-host.ai/connectingCaptions) · [For work](https://chrisswimlee.com/connectingCaptions/license/)

**For work:** a named license is $60 per Mac per year, five Macs minimum. Prices are on the [license page](https://chrisswimlee.com/connectingCaptions/license/). The app stays free for everyone, work use included.

---

## Theater captions

1. Use **macOS 15** or later on Apple Silicon. First run uses Apple Speech (Analyzer on macOS 26). Same-language captions need no translation pack.
2. First run covers Welcome, your languages, Voice Engine, the microphone, then **Listen**. It ends when a sentence appears. **Show original text** is Off or On the board. On the board prints the original under Show-as when the sentence is ready. Line print defaults to at once. **Voice Engine** and **Language packs** are Setup tabs. Voice Engine recognizes speech using the selected model. Translation Engine is Apple Translation. Speech assets and translation packs download separately.
3. Allow the microphone. **Listen** stays off until Voice Engine and (for Translate) the pack are green.
4. Optional: import notes or a deck on Theater Home for this talk. Names stay on this Mac. Speak one sentence. **Listen, then type** unlocks after that first caption. **Type the board** types captions already printed. **Copy** always takes everything on screen. **Clear** wipes the board. Talk notes stay. Listen can keep going.

In **Overlay**, choose **Unlock text area** from the hover controls or the menu-bar Theater menu. Drag to move it, resize its edges or corners, then choose **Lock text area**. The saved area stays fixed even while Tools are visible.

Accessibility permission is only required if you want a translation typed into other apps. Theater captions on your screen do not need it.

---

## How Theater works

Theater is a measured on-device pipeline, not a cloud caption API.

1. **Capture** — A first-party Core Audio HAL path, not `AVAudioEngine` on the live path. It captures from any Core Audio input device, not just the built-in microphone: wired, USB, or line-in gear, Bluetooth headsets in call (HFP) mode, and virtual loopback inputs such as BlackHole or Loopback when you route system or app audio into them. Voice and Translate both use it.
2. **Speech edges** — Live PCM stays in a 30-second ring. The first ASR tick is immediate. After 400 ms of RMS silence, later ticks are skipped so a long pause does not keep the Neural Engine hot. There is no neural VAD in front of first words.
3. **Appear when ready** — What you are saying stays in the bar under the board until the sentence prints. A real clause (finished sentence, or silence/Stop confirmation of a leftover clause) is accepted and appears once. Caption Pause and Stop drop a fragment that is not a real clause. Listen, then type Stop is the only path that still types a trailing fragment. Apple Translation may warm the clause before it appears. Same-language pairs skip the pack. Korean, Japanese, and Thai send the last 4 source clauses from this Listen, then peel the new caption.
4. **Stage window** — A nonactivating panel over Keynote. Screenshots and a whole-screen Zoom or Meet share include Theater. Share the slides window when remote viewers should not see captions. The Show-as title sits above a smaller spoken undertone. Wrap fills left to right. YouTube boilerplate is dropped before print.
5. **Bounded memory** — 30 s of 16 kHz float, unread leftover speech, and the latest 48 board lines. The window shows what fits and can scroll back through those 48. Older lines leave the board and stay in this listen for History and export.
6. **Measured clock** — Theater shows `mic · e2e · ASR · MT` from Core Audio host time. Those values come from a real Listen. Hosted CI cannot prove a live Theater listen.

The systems write-up is [docs/APPLE_SILICON_STREAMING.md](docs/APPLE_SILICON_STREAMING.md). Latency budgets and the HUD are in [docs/LIVE_TRANSLATION_LATENCY.md](docs/LIVE_TRANSLATION_LATENCY.md).

---

## Features

- **Languages** — I speak lists the selected engine’s confirmed speech languages. Show as lists compatible translation pairs. The same language needs no translation pack.
- **Theater captions** — a floating window you turn on and close. Use **Pop-up** for a solid board or **Overlay** so only caption text sits on slides. Change Overlay font, size, and plate from the menu-bar Theater menu. On-screen `mic · e2e · ASR · MT` clock. Screenshots and a whole-screen Zoom or Meet share include Theater. Share the slides window when remote viewers should not see captions. Pause holds capture and drops a leftover; Resume does not bring that leftover back. Minimize hides Theater; Listen stays. Clear wipes the board. Talk notes stay. Lines past the latest 48 leave the board. Translate shows Behind or Caught up so you do not outrun the caption. A sentence appears once when it is accepted. The board is not a text field.
- **Any input device** — capture works with any Mac input, not just the built-in microphone: wired, USB, or line-in gear, Bluetooth headsets in call (HFP) mode, and virtual loopback devices (BlackHole, Loopback) when audio is routed to them. Choose devices in Settings → **Audio Devices**: the **Input Device Priority** list can be dragged to reorder, and a cleared list falls back to the last device you used if it is still connected, otherwise the system default input. A newly connected device becomes the fallback at once and takes over as soon as the top choice is unplugged.
- **Original language / Translate** — both use the selected Voice Engine. Translate uses Apple Translation on this Mac for the pair you set. Press the mode control to switch. Both use the selected input device.
- **Translate into an app** — a separate shortcut from dictation; types this listen’s translation into the app you clicked, including a trailing fragment. Korean, Japanese, and Thai depend on that app’s input method. Accessibility is required.
- **On-device translation** — Apple Translation language packs, processed locally
- **Apple Speech** — Analyzer on macOS 26, otherwise the older Apple Speech. Offline language support varies by Mac; Analyzer may need speech assets.
- **Local-first** — voice and text stay on your Mac. Theater does not send captions to a cloud API.
- **Menu bar access** — start, stop, and open settings from the menu bar

---

## Supported Models

Voice Engine lists every available model with **Supported languages**, **Ready on
this Mac**, and the status of the current I speak language. Apple engines are built
in, but this does not guarantee that a particular language works offline or has
its speech assets installed. Other engines use a model download.

Whisper, Parakeet, Cohere, and Nemotron appear where enabled for this Mac. The
app’s supported language lists reflect its integrated routes. For example,
Parakeet is currently exposed for English, Cohere excludes Thai, and Nemotron’s
Thai route remains experimental. Whisper supports Thai.

**Language Packs** only shows supported Apple Translation pairs for I speak.
**Either way** appears when Whisper Small is installed and translation is ready in
both directions. Turning it off keeps the selected engine.

See [Speech and translation support](docs/LANGUAGE_SUPPORT.md) for the capability
checks and download behavior.

---

## Install

**Preferred.** Download [Connecting-Captions.zip](https://github.com/chrisswimlee/connectingCaptions/releases/latest/download/Connecting-Captions.zip). That name tracks the latest release. A notarized Developer ID zip should stay quiet in Gatekeeper. Drag **Connecting Captions** to Applications, open Theater, allow the microphone, and press **Listen**.

**Homebrew.**

```bash
brew tap chrisswimlee/connectingcaptions
brew trust chrisswimlee/connectingcaptions
brew install --cask connectingcaptions
```

**Preview zip (unsigned).** If only a pre-release is published, download `Connecting-Captions-{version}-preview-unsigned.zip`. macOS blocks it the first time: click **Done**, then **System Settings → Privacy & Security → Open Anyway**. In-app updates stay off for previews.

**Build from source (Xcode).** Permissions stay across rebuilds. See [Building from Source](#building-from-source).

The app is unsandboxed (Hardened Runtime on). Theater needs microphone access. Insert-into-another-app needs Accessibility. Apple Translation packs download on first use when I speak and Show as differ; they are not inside the zip.

Maintainers: push a tag like `preview-1.6.12-1` (`git tag preview-1.6.12-1 && git push origin preview-1.6.12-1`) and the Preview workflow publishes that commit as a pre-release (`./build.sh preview`). A signed release needs a Developer ID: `./build.sh release` with `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD`, then a `v*` tag such as `v1.6.12` runs `.github/workflows/release.yml`. Hosted CI cannot prove a live Theater listen.

---

## Requirements

- macOS 15.0 (Sequoia) or later. Theater Listen, Voice, Translate, and language swap work on 15. Apple Speech Analyzer needs macOS 26.
- Apple Silicon Mac for Theater. Apple Speech also runs on Intel, but that is not the Theater path
- Disk space for an Apple Translation pack when I speak and Show as differ
- Microphone access for Theater and dictation
- Accessibility permissions if you want a translation typed into other apps
- Download the Apple Translation pack once before a cross-language Listen. Same-language captions do not need a pack.

---

## Building from Source

You need an Apple Silicon Mac on macOS 15 or later, **Xcode 26** (CI uses 26.3), and a free Apple Account. No paid developer membership.

1. **Get a free signing certificate** (once). In Xcode, open **Settings → Accounts**, add your Apple Account, select its **Personal Team**, click **Manage Certificates…**, then **+ → Apple Development**. Signing keeps Microphone and Accessibility granted across rebuilds.

2. **Clone and build:**

   ```bash
   git clone https://github.com/chrisswimlee/connectingCaptions.git
   cd connectingCaptions
   ./build.sh
   ```

   `./build.sh` finds your Apple Development certificate and its team. The first build resolves Swift packages and takes several minutes. With more than one team, pin one:

   ```bash
   cp xcconfig/Local.xcconfig.example xcconfig/Local.xcconfig
   # set DEVELOPMENT_TEAM to your 10-character team ID
   ```

3. **Launch** `DerivedData/Build/Products/Debug/Connecting Captions Debug.app`. Always launch this same path after rebuilding so macOS keeps its permissions.

4. **First run.** Open **Theater**, allow the microphone, pick **Original language** or **Translate**, and press **Listen**. For Translate, download the Apple Translation pack when asked. Allow Accessibility only if you use Type the board or Listen, then type.

5. **Update later:**

   ```bash
   git pull
   ./build.sh
   ```

No certificate? `./build.sh unsigned` builds without one, but macOS may ask for Accessibility again after each rebuild. You can also open `connectingCaptions.xcodeproj` and run from Xcode. App Swift packages are pinned in `connectingCaptions.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`; root `Package.swift` only builds the C capture helper.

Architecture notes live in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Latency budgets and the Theater HUD are in [docs/LIVE_TRANSLATION_LATENCY.md](docs/LIVE_TRANSLATION_LATENCY.md). Score a recorded talk with [docs/STAGE_SCORE.md](docs/STAGE_SCORE.md). Signing and notarization are in [docs/SIGNING.md](docs/SIGNING.md). The systems write-up is [docs/APPLE_SILICON_STREAMING.md](docs/APPLE_SILICON_STREAMING.md).

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the first hour (Release zip or signed `./build.sh`, Apple Speech, Theater on macOS 15+, `./scripts/format-and-lint.sh`, tests minus UITests). Please read the [code of conduct](CODE_OF_CONDUCT.md) and [security policy](SECURITY.md) before opening an issue or pull request.

When a change belongs in the upstream dictation engine rather than translation or captions, file it on [FluidVoice](https://github.com/altic-dev/FluidVoice). Starter tickets are listed in [.github/GOOD_FIRST_ISSUES.md](.github/GOOD_FIRST_ISSUES.md).

---

## Run tests

For a complete local validation with saved logs, run `sh scripts/validate-release.sh`.
The [release validation guide](docs/RELEASE_VALIDATION.md) covers real microphone,
IME, offline, installer and demo checks. Export **Quality review (JSONL)** from
Theater to prepare human-reviewed recognition and translation measurements.

Settings → General → **App language** offers all setup languages for interface
copy. Additional interface translations run on this Mac and are cached locally;
Apple may request a language pack. English remains available during preparation.
The app language is independent of I speak and Show as.

Full local run, matching the `Build and Test` CI gate (CI skips the Theater smoke and
the flaky Tiny Whisper E2E because hosted runners can't prove either):

```bash
xcodebuild test -project connectingCaptions.xcodeproj -scheme connectingCaptions \
  -destination 'platform=macOS,arch=arm64' \
  -skip-testing:ConnectingCaptionsUITests \
  -skip-testing:ConnectingCaptionsIntegrationTests/DictationE2ETests/testDictationEndToEnd_whisperTiny_transcribesFixture
```

CI runs the guard chain before that test command, in this order: test wiring, team ID, UI copy, quality-scorer vectors, interface catalog, Python tooling tests, SwiftLint strict, then the two standalone harnesses and `xcodebuild test` with the two skips above:

```bash
sh scripts/test-omitted-tests.sh
bash scripts/check-team-id.sh
sh scripts/test-ui-copy.sh
sh scripts/test-quality-score.sh
python3 scripts/update-interface-catalog.py --check
python3 -m unittest discover -s scripts -p 'test_*.py'
sh Tests/run_paste_key_cache_tests.sh
sh Tests/run_history_persistence_tests.sh
```

The paste-key and history harnesses are **not** XCTest targets — they compile via `swiftc` in those scripts (CLT or full Xcode). Pass `--live` to the paste harness only on a local Mac with Accessibility; CI never passes that flag.

---

## Privacy

Connecting Captions is **local-first**. Your voice, audio, and transcribed text never leave your machine unless you explicitly opt in to a cloud AI provider.

This release does not send analytics, feedback, or update checks to a third-party analytics host. Voice Engine weights stay in this app's folder. A model already in the shared FluidAudio cache is copied once, and that cache is not deleted. A FluidVoice install on the same Mac is left alone: this app does not read or delete that app's Keychain or Application Support folder.

**Not collected:**

- Voice, raw audio, or transcribed text
- Selected text, prompts, or AI responses
- Terminal commands, window titles, file paths, clipboard, or typed content

---

## Commercial license

connectingCaptions is free for everyone under GPLv3, work use included. Theater Listen stays unlocked. A commercial license is optional.

Firms that need a vendor they can sanction — a named license, a security contact, or a written SLA — buy at the published price:

- [chrisswimlee.com/connectingCaptions/license](https://chrisswimlee.com/connectingCaptions/license/) — $60 / Mac / year, five Macs minimum; SLA +$90 / Mac / year; MDM pkg $1,500 once
- Email [suyoung.lee99@gmail.com](mailto:suyoung.lee99@gmail.com?subject=Connecting%20Captions%20commercial%20license) with the organization and Mac count

A paid key is air-gapped. It replaces the in-app work notice with **Licensed to** your organization. It does not phone home. A written SLA and a signed seat list are optional. A Jamf or Fleet package can install the key, the seat list, and caption settings. The on-device audit log stores no captions. See [docs/COMMERCIAL.md](docs/COMMERCIAL.md).

This is not consulting. Consulting is [Engage](https://chrisswimlee.com/engage/).

## Credits

Speech recognition comes from [FluidVoice](https://github.com/altic-dev/FluidVoice) by altic-dev under GPLv3. Theater captions and insert are this product.

---

## License

From 2026-02-23 onward, this project is licensed under the [GNU General Public License, Version 3.0 (GPLv3)](LICENSE).

Versions published before this date were licensed under Apache License 2.0.

Third-party notices for models, frameworks, and logos are in [NOTICE](NOTICE).
