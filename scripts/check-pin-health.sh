#!/bin/sh
# Dependency Pin Health: weekly CI tripwire for pinned package revisions.
#
# Why this exists: the app pins two fork revisions (FluidAudio and
# DynamicNotchKit are pinned with kind = revision at a fixed SHA, and those
# forks publish no tags, so a tag pin is not an option here). A pinned
# commit can quietly become unreachable when upstream force-pushes or garbage
# collects it. Nothing fails until a clean resolve happens - a hosted CI run
# with a cold cache, or a Mac that clones fresh from origin - and by then the
# breakage lands on whoever is mid-release. This probe catches the drift
# weekly in CI, with no Mac in the cloud, no secrets, and no Xcode.
#
# What it checks: for every pin in BOTH Package.resolved files (the workspace
# one that the app target resolves from, and the root one), the pinned
# 40-character revision is fetched with depth 1 from its remote. GitHub (and
# any git host that honors fetch-by-sha) can only serve a revision that is
# still a ref tip or reachable from a live ref, so a failed fetch means the
# pin is gone from the remote and the next clean resolve WILL fail.
#
# Usage: sh scripts/check-pin-health.sh   (also run weekly by
# .github/workflows/dependency-health.yml; needs sh + git + network only)

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
work="$(mktemp -d "${TMPDIR:-/tmp}/cc-pin-health.XXXXXX")"
trap 'rm -rf "$work"' EXIT

: > "$work/pairs"
: > "$work/seen"

collect_pairs() {
    resolved="$1"
    if [ ! -f "$resolved" ]; then
        echo "MISSING PIN FILE (pin health trusts nothing else): $resolved"
        fail=1
        return
    fi
    # One "location" + one "revision" per pin entry, either file format.
    awk -F'"' '
        $2 == "location" { url = $4; next }
        $2 == "revision" { if (url != "") print url " " $4; url = "" }
    ' "$resolved" >> "$work/pairs"
}

while IFS= read -r resolved; do
    collect_pairs "$resolved"
done <<LIST
$ROOT/connectingCaptions.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
$ROOT/Package.resolved
LIST

checked=0
while read -r url rev; do
    [ -n "$url" ] || continue
    grep -qxF "$url $rev" "$work/seen" && continue
    checked=$((checked + 1))
    echo "$url $rev" >> "$work/seen"
    case "$rev" in
        *[!0-9a-f]*)
            echo "MALFORMED PIN: $url @ $rev"
            fail=1
            continue
            ;;
    esac
    case "$url" in
        https://*|http://*|ssh://*|git://*|file://*) ;;
        *)
            echo "MALFORMED PIN URL: $url"
            fail=1
            continue
            ;;
    esac
    rm -rf "$work/probe"
    git init -q "$work/probe" || { echo "GIT INIT FAILED (local git broken?): $url"; fail=1; continue; }
    git -C "$work/probe" remote add origin "$url"
    # A fresh shallow fetch proves the remote can still serve the pinned
    # commit today. Reachable-from-any-ref and ref-tip pins both pass.
    if git -C "$work/probe" fetch -q --depth=1 --no-tags origin "$rev" 2>"$work/probe.err"; then
        echo "OK          $url @ $(printf '%s' "$rev" | cut -c1-12)"
    else
        echo "UNREACHABLE $url @ $(printf '%s' "$rev" | cut -c1-12) -- remote said: $(tr '\n' ' ' < "$work/probe.err" | sed 's/^ *//; s/ *$//')"
        fail=1
    fi
done < "$work/pairs"

if [ "$fail" = 1 ]; then
    cat <<'HINT'

A pinned revision is no longer fetchable from its remote (or a Package.resolved
file went missing). Any clean resolve - hosted CI with a cold cache, or a Mac
that clones fresh from origin - would now fail on that dependency. A re-pin to
a different commit is a behavior change, not a chore: give it its own PR with
notes explaining the code change, and never re-pin quietly inside a release PR.
HINT
    exit 1
fi

if [ "$checked" = 0 ]; then
    # A present-but-empty pins array reaches the same exit 0 as a fully
    # verified lockfile, so say what was actually proven instead of a bare OK.
    echo "dependency pin health: NOTHING PROVEN (0 pinned revisions found in either Package.resolved - nothing was fetched)"
    exit 0
fi

echo "dependency pin health: OK ($checked pinned revisions fetchable from their remotes)"
exit 0
