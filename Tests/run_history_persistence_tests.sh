#!/bin/sh
# Standalone harness for HistoryPersistenceBoundaryTests.swift.
# Compiles the history persistence sources with the test's local doubles (no XCTest).
# CI-safe: works with Command Line Tools or full Xcode (needs AppKit + SQLite3).
set -eu

task_repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_test_dir=$(mktemp -d /tmp/connectingcaptions-history-tests.XXXXXX)
trap 'rm -rf "$task_test_dir"' EXIT

sdk_path=$(xcrun --sdk macosx --show-sdk-path)
xcrun swiftc -O -sdk "$sdk_path" -framework AppKit -framework Foundation \
    "$task_repo_dir/Sources/ConnectingCaptions/Persistence/AppSupportDirectory.swift" \
    "$task_repo_dir/Sources/ConnectingCaptions/Persistence/TranscriptionHistoryDatabase.swift" \
    "$task_repo_dir/Sources/ConnectingCaptions/Persistence/TranscriptionHistoryStore.swift" \
    "$task_repo_dir/Tests/HistoryPersistenceBoundaryTests.swift" \
    -o "$task_test_dir/history-persistence-tests"
"$task_test_dir/history-persistence-tests"
