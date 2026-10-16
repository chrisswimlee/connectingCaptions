# Contributing to Connecting Captions

This repo is Theater captions and dictation insert for the setup languages: every language both Apple Translation and a Voice Engine can use. Translate follows I speak into Show as. Speech recognition engines come from [FluidVoice](https://github.com/altic-dev/FluidVoice). Theater Listen, captions, History, and the app identity are owned here. See [CREDITS.md](CREDITS.md). Please follow the [Code of Conduct](CODE_OF_CONDUCT.md). Report security issues only through [SECURITY.md](SECURITY.md). Commercial and procurement questions go to [docs/COMMERCIAL.md](docs/COMMERCIAL.md) or [chrisswimlee.com/connectingCaptions/license](https://chrisswimlee.com/connectingCaptions/license/), not GitHub Issues.

## Who this repo is for

| Change | File it here | File it upstream |
| --- | --- | --- |
| Theater window, Voice / Translate, captions, Apple Translation, latency HUD | Yes | No |
| Theater Listen start/stop, partial bus, History, connectingCaptions identity | Yes | No |
| Dictation insert of **this Listen** into another app | Yes | Only if the typing engine itself is wrong |
| Voice Engine picker for the setup languages | Yes | No |
| ASR decode, input-device capture graph (mic, USB/line-in, Bluetooth, virtual loopback), Parakeet / Whisper / Nemotron internals | Ask first | Usually [FluidVoice](https://github.com/altic-dev/FluidVoice) |
| Command Mode, rewrite, file transcription, local HTTP API, PostHog | No — those were removed | FluidVoice if they still exist there |

Ready starter tickets live in [.github/GOOD_FIRST_ISSUES.md](.github/GOOD_FIRST_ISSUES.md). `scripts/enable-github-gates.sh` files them with `good first issue` when the repo is public.

## Do not edit

Leave these FluidVoice-era files alone unless the accepted issue is about that engine or shell:

- `ASRService.swift` and `ASRService+*.swift` — Theater may skip a pause-only decode and leave a quiet stretch out of a trailing-window tick. That lives in `PauseIntervalAudio` and is called from `ASRService+DevicesAndStreaming.swift`, `ASRService+Start.swift`, and `ASRService+Stop.swift`. Other ASR work still belongs upstream.
- `ContentView.swift` (routing goes in `ContentView+*.swift`)
- `MenuBarManager.swift`
- `CustomDictionaryView.swift`

New Theater work belongs in `Sources/ConnectingCaptions/Services/LiveTranslation/` or `Sources/ConnectingCaptions/UI/LiveTranslation/`. New settings go in `SettingsStore+*.swift`. Do not add product surfaces to files marked `Tracked grandfather`.

## First hour

You need an **Apple Silicon** Mac. Theater Listen, Voice, Translate, and language swap work on **macOS 15** and later. Apple Speech Analyzer needs **macOS 26**.

1. **Install (preferred):** download `Connecting-Captions-{version}.zip` from [GitHub Releases](https://github.com/chrisswimlee/connectingCaptions/releases) and open the app. A notarized Developer ID zip should stay quiet in Gatekeeper.

2. **Or build** if you are changing the tree. A free Personal Team is enough:

```bash
cp xcconfig/Local.xcconfig.example xcconfig/Local.xcconfig
# set DEVELOPMENT_TEAM
./build.sh
```

Launch `DerivedData/Build/Products/Debug/Connecting Captions Debug.app`. Keep using that product so macOS can keep Accessibility and Microphone. An unsigned or ad-hoc rebuild can drop those grants; allow **Connecting Captions Debug** again in System Settings → Privacy & Security.

3. First run selects **Apple Speech Analyzer** on macOS 26, otherwise **Apple Speech**, and ends when a sentence appears. Setup is **Voice Engine** and **Language packs**. Either way downloads **Whisper Small** once.

4. Allow the microphone. Pick **Voice** for the language you speak or **Translate** for captions. Press **Listen** and speak one sentence. A language pack downloads only when I speak and Show as differ. Theater Listen does not ask for Screen Recording.

5. Format, lint, and test. `./scripts/format-and-lint.sh` is required before you open a PR (SwiftFormat, SwiftLint strict, and the PR-policy unit tests when those tools are installed). CI enforces this chain on every push and PR that touches `Sources/**`, `Tests/**`, `scripts/**`, the Xcode project, or a `Package.resolved` file:

   1. `scripts/test-omitted-tests.sh` — test-wiring guard. Fails when a `Tests/` file compiles in no target or harness; also fails on a committed `DEVELOPMENT_TEAM` in `project.pbxproj`.
   2. `scripts/check-team-id.sh` — team-ID guard (run with `bash`; it needs `pipefail`). Same team-ID rule as a standalone step: none in `project.pbxproj`, and `xcconfig/Local.xcconfig` stays untracked.
   3. `scripts/test-ui-copy.sh` — marketing-copy and VoiceOver-trap guard.
   4. `scripts/test-quality-score.sh` — quality-scorer guard. `TheaterQualityScore.swift` and `scripts/score-theater-talk.py` are two implementations of one WER/CER rule; this fails when they stop counting the same units, and starts scoring `docs/samples/reference.jsonl` the day one is checked in.
   5. `python3 scripts/update-interface-catalog.py --check` and the Python tooling regressions (`python3 -m unittest discover -s scripts -p 'test_*.py'`).
   6. SwiftLint strict (`swiftlint:0.65.1` in docker).
   7. The two `Tests/run_*.sh` harnesses (`swiftc`; Command Line Tools is enough).
   8. `xcodebuild test` on macos-15, minus `ConnectingCaptionsUITests` and the flaky Tiny Whisper E2E.

   A separate, docs-only gate runs on PRs that touch `docs/**` or a top-level `*.md` file (so a docs-only PR doesn't skip CI entirely): `scripts/test-docs-copy.sh` checks for banned marketing copy and broken relative links in markdown.

   The same chain locally (the guards need nothing but `sh`, `bash`, `git`, and `grep`):

```bash
./scripts/format-and-lint.sh
sh scripts/test-omitted-tests.sh
bash scripts/check-team-id.sh
sh scripts/test-ui-copy.sh
sh scripts/test-quality-score.sh
python3 scripts/update-interface-catalog.py --check
python3 -m unittest discover -s scripts -p 'test_*.py'
sh Tests/run_paste_key_cache_tests.sh
sh Tests/run_history_persistence_tests.sh
xcodebuild test -project connectingCaptions.xcodeproj -scheme connectingCaptions \
  -destination 'platform=macOS,arch=arm64' \
  -skip-testing:ConnectingCaptionsUITests \
  -skip-testing:ConnectingCaptionsIntegrationTests/DictationE2ETests/testDictationEndToEnd_whisperTiny_transcribesFixture
```

The Tiny Whisper E2E is skipped in CI only because GGUF output is nondeterministic on hosted runners; keep it green locally.

Paste-key and history persistence tests stay in `Tests/run_*.sh` only (not the Integration Sources phase). Non-live paste + history run in CI. Local-only live layout probe:

```bash
sh Tests/run_paste_key_cache_tests.sh --live
```

`ConnectingCaptionsUITests` is the Theater smoke. It needs macOS UI automation. Local machines can skip it. Hosted CI uses Xcode 26 on a `macos-15` runner; it **cannot** prove a live Theater listen. Prove a talk on your Mac with [docs/STAGE_SCORE.md](docs/STAGE_SCORE.md). Do not invent WER or HUD numbers.

Do not commit `xcconfig/Local.xcconfig` or a `DEVELOPMENT_TEAM` value in `project.pbxproj`. Optional hook:

```bash
cp scripts/check-team-id.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```

Unsigned fallback for machines without a team: `./build.sh unsigned`. To run the tests without a team, sign ad hoc:

```bash
xcodebuild test -project connectingCaptions.xcodeproj -scheme connectingCaptions \
  -destination 'platform=macOS,arch=arm64' \
  -skip-testing:ConnectingCaptionsUITests \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
```

## Dependencies, pins, and second Macs

Every machine that builds this app — both dev Macs and hosted CI — resolves packages from `origin`, never from each other. Two rules keep that chain honest:

- A second dev Mac (or any new machine) clones **from GitHub**, never from a copy of another Mac, and never copies a hand-picked `Package.resolved` with it. Both `Package.resolved` files are tracked, so a fresh clone from `origin` resolves exactly the pins this repo already reviewed.
- `scripts/check-pin-health.sh` — run locally and weekly by `Dependency Pin Health` (`.github/workflows/dependency-health.yml`) — proves every pinned revision in the checked-in `Package.resolved` files is still fetchable from its remote. Hosted CI re-resolves packages on every relevant push, and a `Package.resolved` edit is itself a `build.yml` relevant path. When Pin Health goes red, that is pin drift, not test flakiness.

Never re-pin quietly. `project.pbxproj` pins two forks by **revision**, not by branch (`kind = revision`, no `branch` key): `altic-dev/FluidAudio` at `3fd63887…` and `altic-dev/DynamicNotchKit` at `708f31da…`. Neither fork publishes tags, so "just pin to a tag" does not exist here, and a revision pin is frozen — it will not drift when the fork's branch moves, which is exactly why `scripts/check-pin-health.sh` has to prove those revisions are still fetchable. Changing either SHA means new runtime code, so it is a behavior change and needs its own PR with a change description; never re-pin quietly inside a release PR — that is where release gets blocked.

## Where to edit

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before changing Theater or the speech engine.

| Area | Path | Role |
| --- | --- | --- |
| Live translation | `Sources/ConnectingCaptions/Services/LiveTranslation/` | Clause split, Apple Translation, Theater archive, latency HUD |
| Theater UI | `Sources/ConnectingCaptions/UI/LiveTranslation/` | Home, Theater window, presenter chrome |
| Speech engine | `ASRService.swift` plus `ASRService+*.swift` | Captured audio → transcript, from any selected input device (mic, USB/line-in, Bluetooth, virtual loopback). Reads `SpeechCapturePolicy`. Keep this as the engine, not the product. |
| Theater Listen | `ContentView+TheaterListen.swift`, `TheaterSpeechSession.swift` | Caption and insert start/stop. Do not start Theater as dictation. |
| Dictation insert | `TypingService`, `GlobalHotkeyManager`, `QuickTranslateInsert` | Listen, then type uses the app captured at start and shows that line on a bar. Type the board uses the frontmost field. |
| Overlay | `BottomOverlayView`, `NotchOverlayManager` | Insert chip only |
| Settings | `SettingsStore.swift` plus `SettingsStore+*.swift` | Persist models, shortcuts, Theater options |
| App shell | `ContentView.swift` plus `ContentView+*.swift` | Window, Theater Listen, onboarding |

New settings belong in a `SettingsStore+*.swift` file. New ContentView routing belongs in a `ContentView+*.swift` file. New Theater work stays under `LiveTranslation/`.

## Start with Discussions

Start a [GitHub Discussion](https://github.com/chrisswimlee/connectingCaptions/discussions) first when you want to:

- Ask a support question.
- Propose a broad idea or feature.
- Explore a design direction.
- Report behavior that you are not sure is a connectingCaptions bug.
- Ask whether a change would be accepted before writing code.

Do not open an issue to buy or quote a commercial license. Send IT and legal to [the license page](https://chrisswimlee.com/connectingCaptions/license/). Prices are on that page.

Feature ideas should begin in the Ideas category. Maintainers may turn an accepted discussion into a tracked issue.

## Issues

Issues are for work that maintainers can triage and act on.

Use a bug issue only when you can provide:

- A clear description of the bug.
- Exact reproduction steps.
- Expected behavior and actual behavior.
- connectingCaptions version, macOS version, and architecture.
- Logs, crash reports, screenshots, or recordings when relevant.

Incomplete bug reports may be labeled `needs reproduction`. If the missing details are not provided after 14 days, the issue-intake workflow may close them.

Issues and PRs with no activity are marked stale after 30 days (issues) or 45 days (PRs) and closed 14 days later. Add `keep-open`, `pinned`, `security`, `good first issue`, or `help wanted` to skip that.

## Pull Requests

Pull requests should be tied to an accepted issue, Discussion, or roadmap item. Before opening a PR:

- Fill out every required section of the PR template.
- Select a type of change.
- Link the related issue or accepted Discussion.
- Describe how you tested the change.
- Attach screenshots or video for UI, UX, settings, onboarding, overlay, menu bar, or visual behavior changes.

Docs-only and test-only PRs are not blocked on Theater screenshots. If a PR has no UI or visual behavior changes, check the "No UI/visual changes" box. The PR Policy workflow still requires screenshots or video when changed files touch visual surfaces.

PRs that do not follow the template will be blocked by the `PR Policy` check. If required information is still missing after 7 days, the PR may be closed.

Add a `[Unreleased]` bullet to [CHANGELOG.md](CHANGELOG.md) for user-facing changes.

## Maintainer gates

These are not CI checks. Run [`scripts/enable-github-gates.sh`](scripts/enable-github-gates.sh) as an owner when `gh` is logged in.

- Make `chrisswimlee/connectingCaptions` **public**. In-app update checks, issue templates, and feedback links already point there.
- Enable Issues, Discussions (Ideas / Q&A Help / General), and Private Vulnerability Reporting.
- Require the `Build and Test` check and the `PR Policy` check on `main`.
- Create a GitHub Environment named `release` with required reviewers. The release workflow fails closed unless Developer ID and notarization secrets are present.
- Fill one [stage score](docs/STAGE_SCORE.md) on a real Mac. Do not invent numbers. Watch is not a product gate.
- After the first Developer ID zip, publish a `v*` GitHub Release with `SHA256SUMS`. `ConnectingCaptionsProduct.allowedUpdateTeamIDs` already includes `C6BH3WS28B`. See [docs/SIGNING.md](docs/SIGNING.md).
