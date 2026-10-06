#!/bin/sh
# Keeps Tests/ compiling truth in sync with the harnesses that run it.
#
# Why this exists (2026-10-02 audit):
# - ConnectingCaptionsIntegrationTests compiles from an EXPLICIT file list in
#   project.pbxproj (PBXSourcesBuildPhase), NOT from a synchronized folder. A test file
#   that is in neither that Sources phase nor a Tests/run_*.sh swiftc input never
#   compiles, so nothing fails when test coverage quietly disappears.
# - Mere PBXFileReference / group membership (path = Foo.swift) is NOT enough — that
#   was the SpokenPunctuationFormatting rot mode. Comment mentions in harness scripts
#   also do not count.
#
# What it checks:
# 1. every .swift under Tests/ (except Helpers/ + Resources/ + Fixtures/) appears in a
#    "Foo.swift in Sources" build-phase entry OR as a path-like swiftc input on a
#    non-comment line of Tests/run_*.sh -> catches ORPHANED tests;
# 2. every path = <leaf>.(swift|wav|txt) in project.pbxproj exists on disk under
#    Sources/ or Tests/ (or repo root) -> catches DANGLING build-file entries.
# Exit 1 = drift found. Needs only sh+grep+find+sed; CI-safe (no Xcode required).

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="$ROOT/connectingCaptions.xcodeproj/project.pbxproj"
fail=0

refs="$(mktemp /tmp/cc-refs.XXXXXX)"
trap 'rm -f "$refs" "$refs.dangling" "$refs.ondisk"' EXIT

# Extract only path = Leaf.ext assignments — never lastKnownFileType tokens
# (e.g. audio.wav / sourcecode.swift), which are not file references.
extract_pbx_paths() {
    grep -oE 'path = "?[A-Za-z0-9_+\.-]+\.(swift|wav|txt)"?;' "$1" \
        | sed -E 's/^path = "?//; s/"?;$//' \
        | sort -u
}

# Wired = actually compiled: members of PBXSourcesBuildPhase file lists only.
# Do NOT use bare "Foo.swift in Sources" grep — that also matches PBXBuildFile
# definitions that can linger after a file is dropped from the phase.
awk '
    /isa = PBXSourcesBuildPhase/ { want = 1 }
    want && /files = \(/ { in_files = 1; next }
    in_files && /^[[:space:]]*\);/ { in_files = 0; want = 0; next }
    in_files { print }
' "$PBXPROJ" \
    | grep -oE '[A-Za-z0-9_+]+\.swift in Sources' \
    | sed 's/ in Sources$//' \
    | sort -u > "$refs"

# Standalone harness scripts: only path-like .swift tokens on non-comment lines
# (e.g. "$task_repo_dir/Tests/Foo.swift"), never comment mentions.
for runner in "$ROOT"/Tests/run_*.sh; do
    [ -f "$runner" ] || continue
    grep -v '^[[:space:]]*#' "$runner" \
        | grep -ohE '[A-Za-z0-9_./-]+\.swift' \
        | grep '/' \
        | while IFS= read -r path; do
            basename "$path"
        done >> "$refs" || true
done
sort -u "$refs" -o "$refs"

# 1) ORPHANS: test files referenced by no compile harness.
# Allowlist knob (rare): export CC_OMIT_TESTS_ALLOWLIST='Name.swift:Other.swift'
while IFS= read -r swift; do
    [ -n "$swift" ] || continue
    leaf="${swift##*/}"; leaf="${leaf##* }"
    case "$swift" in
        */Helpers/*|*/Resources/*|*/Fixtures/*) continue ;;
    esac
    skip_orphan=0
    IFS=':'
    for allowed in ${CC_OMIT_TESTS_ALLOWLIST:-}; do
        if [ "$allowed" = "$leaf" ]; then
            skip_orphan=1
            break
        fi
    done
    unset IFS
    [ "$skip_orphan" = 1 ] && continue
    if ! grep -qxF "$leaf" "$refs"; then
        echo "ORPHANED TEST (compiled nowhere): $swift"
        fail=1
    fi
done <<LIST
$(find "$ROOT/Tests" -name '*.swift' -not -path '*/Resources/*' -not -path '*/Fixtures/*' -not -path '*/Helpers/*' | sort -u)
LIST

# 2) DANGLING REFS: path= leaf names in pbxproj with no file on disk.
extract_pbx_paths "$PBXPROJ" > "$refs.dangling"
find "$ROOT/Sources" "$ROOT/Tests" -type f \( -name '*.swift' -o -name '*.wav' -o -name '*.txt' \) \
    -exec basename {} \; | sort -u > "$refs.ondisk"
while IFS= read -r leaf; do
    [ -n "$leaf" ] || continue
    if ! grep -qxF "$leaf" "$refs.ondisk"; then
        # allow names that live at repo root legitimately (e.g. Package.swift)
        [ -f "$ROOT/$leaf" ] && continue
        echo "DANGLING PBXPROJ REFERENCE: $leaf (in project.pbxproj, absent from Sources/ Tests/ on disk)"
        fail=1
    fi
done < "$refs.dangling"

if [ "$fail" = 1 ]; then
    cat <<'HINT'

Fix options (per file):
  * Uncompiled test file -> re-add it to the test target's Sources phase in Xcode, or as a
    swiftc input path in a Tests/run_*.sh harness; or delete it if the code path has moved on.
  * Dangling pbxproj reference -> the file moved (or died) — fix or remove the entry.
HINT
  exit 1
fi
echo "test-harness audit: OK (all Tests/*.swift wired; no dangling references)"
