#!/bin/sh
# Standalone paste-key harness (no XCTest). Non-live suites are CI-safe under
# Command Line Tools or full Xcode. Pass --live for the CGEventPostToPid layout
# probe (local-only; needs Accessibility + a full session).
set -eu

if ! command -v xcrun >/dev/null 2>&1 || ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "swiftc not found via xcrun. Install Xcode or Command Line Tools." >&2
    exit 1
fi

task_repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_test_dir=$(mktemp -d /tmp/connectingcaptions-paste-cache-tests.XXXXXX)
trap 'rm -rf "$task_test_dir"' EXIT
sdk_path=$(xcrun --sdk macosx --show-sdk-path)

xcrun swiftc -O -sdk "$sdk_path" -framework Carbon -framework CoreGraphics -framework Foundation \
    "$task_repo_dir/Sources/ConnectingCaptions/Services/PasteKeyCodeCache.swift" \
    "$task_repo_dir/Tests/PasteKeyCodeCacheRegressionTests.swift" \
    -o "$task_test_dir/paste-cache-tests"
"$task_test_dir/paste-cache-tests"
xcrun swiftc -O -sdk "$sdk_path" -framework Carbon -framework CoreGraphics -framework Foundation \
    "$task_repo_dir/Sources/ConnectingCaptions/Services/PasteKeyCodeResolver.swift" \
    "$task_repo_dir/Tests/PasteKeyCodeResolverTests.swift" \
    -o "$task_test_dir/paste-resolver-tests"
"$task_test_dir/paste-resolver-tests"
if [ "${1:-}" = "--live" ]; then
    xcrun swiftc -O -sdk "$sdk_path" -framework Carbon -framework CoreGraphics -framework Foundation \
        "$task_repo_dir/Sources/ConnectingCaptions/Services/PasteKeyCodeCache.swift" \
        "$task_repo_dir/Sources/ConnectingCaptions/Services/PasteKeyCodeResolver.swift" \
        "$task_repo_dir/Tests/PasteKeyCodeCacheLiveLayoutTests.swift" \
        -o "$task_test_dir/paste-live-tests"
    "$task_test_dir/paste-live-tests"
fi
