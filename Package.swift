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
        .library(name: "SQLCipher", type: .static, targets: ["SQLCipher"]),
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
        .target(
            name: "SQLCipher",
            path: "ThirdParty/SQLCipher",
            sources: ["src/sqlite3.c"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("include"),
                .define("NDEBUG"),
                .define("SQLITE_HAS_CODEC"),
                .define("SQLITE_TEMP_STORE", to: "2"),
                .define("SQLITE_THREADSAFE", to: "1"),
                .define("SQLITE_ENABLE_FTS5"),
                .define("SQLITE_ENABLE_MATH_FUNCTIONS"),
                .define("SQLITE_ENABLE_PERCENTILE"),
                .define("SQLITE_HAVE_ZLIB", to: "1"),
                .define("SQLITE_EXTRA_INIT", to: "sqlcipher_extra_init"),
                .define("SQLITE_EXTRA_SHUTDOWN", to: "sqlcipher_extra_shutdown"),
                .define("SQLCIPHER_CRYPTO_CC"),
                .unsafeFlags(["-w"]),
            ],
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("Foundation"),
                .linkedLibrary("z"),
            ]
        ),
    ]
)
