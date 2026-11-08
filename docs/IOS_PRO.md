# Connecting Captions Pro for iPhone and iPad

Direct download. Scheme `ConnectingCaptionsProIOS`. Bundle ID `com.connectingcaptions.ios.pro`.

This is the full Pro product on iPhone and iPad. Voice Engine is FluidVoice: Parakeet EOU at 160, 320, or 1280 ms, and Nemotron streaming at 560 or 1120 ms. The first Listen downloads the model you pick. Show as is on-device Apple Translation. Pause, undo, copy, and clear are on the board. Adjust sets the caption size, the original line, read-aloud, and a Bluetooth or wired microphone. The Connecting Captions Pro keyboard inserts the last line.

Connecting Captions on the Mac App Store is the smaller build: Apple Speech, the microphone, and the board. Whisper, a virtual loopback device, and a click-through overlay need macOS, so they stay on the direct Mac download.

## License

This download does not ask for a key, matching the Mac app while `ConnectingCaptionsProduct.directDownloadAsksForKey` is false. Listen starts without a trial clock. A Connecting Captions Pro key can still be pasted. It is checked on this device and stored in the keychain. A key that requires a Mac seat list does not unlock the phone. When the switch is turned on, fourteen UTC days run from the first Listen, and a keychain read failure keeps Listen off. Deleting the app removes that clock.

## Install

iOS will not open an unsigned zip. `./scripts/export-ios-pro.sh` archives a signed IPA for devices on the team:

```bash
./scripts/export-ios-pro.sh              # development
./scripts/export-ios-pro.sh ad-hoc       # registered devices
./scripts/export-ios-pro.sh enterprise   # in-house, employees of that organization
```

Set `DEVELOPMENT_TEAM` in `xcconfig/Local.xcconfig` first. The Pro app group is `group.com.connectingcaptions.ios.pro`. Install the IPA with Xcode, Apple Configurator, or the enterprise portal.

Simulator:

```bash
xcodebuild -project connectingCaptions.xcodeproj -scheme ConnectingCaptionsProIOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

The UI smoke does not start Listen:

```bash
xcodebuild test -project connectingCaptions.xcodeproj -scheme ConnectingCaptionsProIOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ConnectingCaptionsProIOSUITests
```

Hosted CI cannot prove a live Listen.
