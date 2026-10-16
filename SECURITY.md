# Security Policy

## Supported versions

Please report vulnerabilities against the current `main` branch of connectingCaptions.

## Reporting a vulnerability

Do not open a public issue for a security report.

Email [suyoung.lee99@gmail.com](mailto:suyoung.lee99@gmail.com) with:

- A description of the issue and its impact
- Steps to reproduce, or a proof of concept if you have one
- The connectingCaptions version, macOS version, and architecture

If the repository has GitHub Private Vulnerability Reporting enabled, you may also use **Security → Report a vulnerability**.

You should hear back within 7 days. Please give us a reasonable window to ship a fix before any public disclosure.

## Scope

In scope:

- Unauthorized access to transcripts, audio history, API keys, or Keychain items
- Update download or code-signature bypass
- Path traversal or unsafe model-file handling

Out of scope:

- Issues that require a compromised local user account
- Denial of service against your own Mac
- Missing features or product requests

## Notes for this build

The app is **unsandboxed**. Theater and dictation need the microphone — that is, the Microphone (audio-input) permission, which covers every capture source: built-in mic, wired/USB/line-in gear, Bluetooth (HFP) headsets, and virtual loopback devices such as BlackHole when audio is routed into them. Insert-into-another-app needs Accessibility. Global hotkeys and user-downloaded voice weights also need to run outside the App Sandbox. Hardened Runtime stays on.

`com.apple.security.cs.disable-library-validation` is still set because Xcode’s XCFramework copy of `CTranscribe.framework` (TranscribeCpp / Whisper) can fail to load after its versioned layout is flattened. Nothing else here needs an exemption: the app no longer ships a Python runtime or a local model server, and the Whisper runtime is linked, not launched as a privileged helper. A Theater-only build that drops Whisper can remove the key. See [docs/SIGNING.md](docs/SIGNING.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

Automatic updates only install a zip that:

- matches `SHA256SUMS` on the GitHub Release
- contains a single top-level `Connecting Captions.app`
- passes `codesign --verify --deep --strict`
- uses bundle id `com.connectingcaptions.app`
- is signed with a usable Developer ID team, not ad-hoc or `not set`

GitHub Release jobs fail closed when Developer ID or notarization credentials are missing. This tree does not ship a local HTTP API or analytics. Live Theater does not send telemetry.

Speech and prompt diagnostics use character counts and provider error identities.
Older builds may have stored speech or provider response text in diagnostic logs,
independently of the transcript-history preference. Settings → Debug Settings →
**Clear Diagnostic Logs** removes this app's current, rotated, and legacy logs.
Review any previously exported diagnostic files separately; clearing local logs
does not remove copies you have shared.

Update replacement retains the displaced app bundles until the replacement
relaunches. If automatic recovery fails, the error identifies the recovery
directory; retain its contents until the app has been recovered. Validate signed
update and rollback in a disposable test account before distributing a release.
