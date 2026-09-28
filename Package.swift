// swift-tools-version: 5.9
// The app is connectingCaptions.xcodeproj. This package only builds the C capture
// helper. An executable target here launches a bare binary and AppKit crashes
// with bundleProxyForCurrentProcess is nil.

import PackageDescription

let package = Package(
    name: "connectingCaptions",
    platforms: [
        .macOS("15.0"),
    ],
    products: [
        .library(name: "CoreAudioCaptureSupport", targets: ["CoreAudioCaptureSupport"]),
    ],
    targets: [
        .target(
            name: "CoreAudioCaptureSupport",
            path: "Sources/CoreAudioCaptureSupport",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
            ]
        ),
    ]
)
