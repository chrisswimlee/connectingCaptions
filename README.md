# Connecting Captions

<p align="center">
  <img src="docs/screenshots/app-icon.png" width="96" alt="Connecting Captions icon">
</p>

**Each sentence appears when it is ready.**

Connecting Captions is live subtitles for macOS, with translation on the machine. Set **I speak** and **Show as** to any language in the setup list, the languages both Apple Translation and a Voice Engine can use. Translate follows I speak into Show as. The same language needs no download. A sentence appears when it is ready. Best with one speaker and a close mic.

![Translate home](docs/screenshots/translate-home.png)

Open **Theater**, set **I speak** and **Show as**, then press **Open Theater** and **Listen**. A new Listen starts with an empty board. Closing Theater hides the window; it does not keep the last talk for the next Listen. A separate shortcut types the current translation into another app. Translation uses Apple’s on-device Translation framework.

![Theater captions](docs/screenshots/theater.png)

By [Chris Swim Lee](https://chrisswimlee.com). Licensed under GPLv3.

[Download](https://github.com/chrisswimlee/connectingCaptions/releases/latest/download/Connecting-Captions.zip) · [Homebrew](https://github.com/chrisswimlee/homebrew-connectingcaptions) · [Product page](https://local-host.ai/connectingCaptions) · [For work](https://chrisswimlee.com/connectingCaptions/license/)

**For work:** if IT or legal need a named commercial license or an SLA, [request one](https://chrisswimlee.com/connectingCaptions/license/). The app stays free for everyone, work use included.

---

## Theater captions

1. Use **macOS 15** or later on Apple Silicon. First run uses Apple Speech (Analyzer on macOS 26). Same-language captions need no translation pack.
2. First run is Welcome, your languages, the microphone, then **Listen**. It ends when a sentence appears. **Spoken line** is Off or On the board. On the board prints the original under Show-as when the sentence is ready. Line print defaults to at once. **Voice Engine** and **Language packs** are Setup tabs. Voice Engine is Apple Speech on this Mac. Translation Engine is Apple Translation (not a chat model). A language pack downloads only when I speak and Show as differ.
3. Allow the microphone. **Listen** stays off until Voice Engine and (for Translate) the pack are green.
4. Optional: import notes or a deck on Theater Home for this talk. Names stay on this Mac. Speak one sentence. **Listen, then type** unlocks after that first caption. **Type the board** types captions already printed. **Copy** always takes everything on screen. **Clear** wipes the board. Talk notes stay. Listen can keep going.

Accessibility permission is only required if you want a translation typed into other apps. Theater captions on your screen do not need it.

---

## How Theater works

Theater is a measured on-device pipeline, not a cloud caption API.

1. **Capture** — The microphone is a first-party Core Audio HAL path, not `AVAudioEngine` on the live path. Voice and Translate both use it.
2. **Speech edges** — Live PCM stays in a 30-second ring. The first ASR tick is immediate. After 400 ms of RMS silence, later ticks are skipped so a long pause does not keep the Neural Engine hot. There is no neural VAD in front of first words.
3. **Appear when ready** — What you are saying stays in the bar under the board until the sentence prints. A real clause (finished sentence, or silence/Stop confirmation of a leftover clause) is accepted and appears once. Caption Pause and Stop drop a fragment that is not a real clause. Listen, then type Stop is the only path that still types a trailing fragment. Apple Translation may warm the clause before it appears. Same-language pairs skip the pack. Korean, Japanese, and Thai send the last 4 source clauses from this Listen, then peel the new caption.
4. **Stage window** — A nonactivating panel over Keynote. Screenshots and a whole-screen Zoom or Meet share include Theater. Share the slides window when remote viewers should not see captions. The Show-as title sits above a smaller spoken undertone. Wrap fills left to right. YouTube boilerplate is dropped before print.
5. **Bounded memory** — 30 s of 16 kHz float, unread leftover speech, and the latest 48 board lines. The window shows what fits and can scroll back through those 48. Older lines leave the board and stay in this listen for History and export.
6. **Measured clock** — Theater shows `mic · e2e · ASR · MT` from Core Audio host time. Those values come from a real Listen. Hosted CI cannot prove a live Theater listen.

The systems write-up is [docs/APPLE_SILICON_STREAMING.md](docs/APPLE_SILICON_STREAMING.md). Latency budgets and the HUD are in [docs/LIVE_TRANSLATION_LATENCY.md](docs/LIVE_TRANSLATION_LATENCY.md).

---

## Features

- **Languages** — I speak and Show as are the setup list. Translate follows I speak into Show as. The same language needs no pack. Apple Speech hears that list.
- **Theater captions** — a floating window you turn on and close. Use **Pop-up** for a solid board or **Overlay** so only caption text sits on slides. Change Overlay font, size, and plate from the menu-bar Theater menu. On-screen `mic · e2e · ASR · MT` clock. Screenshots and a whole-screen Zoom or Meet share include Theater. Share the slides window when remote viewers should not see captions. Pause holds capture and drops a leftover; Resume does not bring that leftover back. Minimize hides Theater; Listen stays. Clear wipes the board. Talk notes stay. Lines past the latest 48 leave the board. Translate shows Behind or Caught up so you do not outrun the caption. A sentence appears once when it is accepted. The board is not a text field.
- **Voice / Translate** — Voice Engine is Apple Speech. Translate uses Apple Translation on this Mac for the pair you set. Press the mode control to switch. Both use the microphone.
- **Translate into an app** — a separate shortcut from dictation; types this listen’s translation into the app you clicked, including a trailing fragment. Korean, Japanese, and Thai depend on that app’s input method. Accessibility is required.
- **On-device translation** — Apple Translation language packs, processed locally
- **Apple Speech** — Analyzer on macOS 26, otherwise the older Apple Speech. No download.
- **Local-first** — voice and text stay on your Mac. Theater does not send captions to a cloud API.
- **Menu bar access** — start, stop, and open settings from the menu bar

---

## Supported Models

I speak and Show as are the setup list: every language both Apple Translation and Apple Speech can use. No Voice Engine download.

| Model | Best for | Hears here | Download size | Hardware |
| --- | --- | --- | --- | --- |
| Apple Speech Analyzer | Newer on-device speech on macOS 26 | Speech Analyzer languages on this Mac | Built-in | Apple Silicon + Intel |
| Apple Speech | The recognizer macOS has included for years | Setup languages | Built-in | Apple Silicon + Intel |

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

4. **First run.** Open **Theater**, allow the microphone, pick **Voice** or **Translate**, and press **Listen**. For Translate, download the Apple Translation pack when asked. Allow Accessibility only if you use Type the board or Listen, then type.

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

## Run Integration Tests

```bash
xcodebuild test -project connectingCaptions.xcodeproj -scheme connectingCaptions -destination 'platform=macOS'
```

CI uses unsigned builds:

```bash
xcodebuild test -project connectingCaptions.xcodeproj -scheme connectingCaptions -destination 'platform=macOS' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

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

Firms that need a vendor they can sanction — a named license, a security contact, or a written SLA — request a commercial license:

- [chrisswimlee.com/connectingCaptions/license](https://chrisswimlee.com/connectingCaptions/license/)
- Email [suyoung.lee99@gmail.com](mailto:suyoung.lee99@gmail.com?subject=Connecting%20Captions%20commercial%20license) with the organization, seat count, and whether you need an SLA

A paid key is air-gapped. It replaces the in-app work notice with **Licensed to** your organization. It does not phone home. A written SLA and a signed seat list are optional. A Jamf or Fleet package can install the key, the seat list, and caption settings. The on-device audit log stores no captions. See [docs/COMMERCIAL.md](docs/COMMERCIAL.md).

This is not consulting. Consulting is [Engage](https://chrisswimlee.com/engage/).

## Credits

Speech recognition comes from [FluidVoice](https://github.com/altic-dev/FluidVoice) by altic-dev under GPLv3. Theater captions and insert are this product.

---

## License

From 2026-02-23 onward, this project is licensed under the [GNU General Public License, Version 3.0 (GPLv3)](LICENSE).

Versions published before this date were licensed under Apache License 2.0.

Third-party notices for models, frameworks, and logos are in [NOTICE](NOTICE).
