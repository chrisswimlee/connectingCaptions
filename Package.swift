// swift-tools-version: 5.9
// The app is connectingCaptions.xcodeproj. This package builds the C capture
// helper and the platform-neutral ConnectingCaptionsCore library. An executable
// target here launches a bare binary and AppKit crashes with
// bundleProxyForCurrentProcess is nil.

import PackageDescription

let package = Package(
    name: "connectingCaptions",
    platforms: [
        .macOS("15.0"),
        .iOS("18.0"),
    ],
    products: [
        .library(name: "CoreAudioCaptureSupport", targets: ["CoreAudioCaptureSupport"]),
        .library(name: "ConnectingCaptionsCore", targets: ["ConnectingCaptionsCore"]),
    ],
    targets: [
        .target(
            name: "CoreAudioCaptureSupport",
            path: "Sources/CoreAudioCaptureSupport",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
            ]
        ),
        .target(
            name: "ConnectingCaptionsCore",
            path: "Sources/ConnectingCaptionsCore"
        ),
    ]
)
