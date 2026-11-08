#!/usr/bin/env sh
# Shared caption math drift gate between this repo and the App Store repo.
#
# The App Store app keeps its own copy of ConnectingCaptionsCore in
# connectingCaptions-iOS/Packages/ConnectingCaptionsCore. It must not take a
# package dependency on this repo, so the copy is synced by hand. This script
# compares every Swift file that exists in both trees and fails on a difference.
#
#   scripts/check-ios-core-drift.sh                 report and fail on drift
#   scripts/check-ios-core-drift.sh --sync PATH...  copy PATH (relative to
#                                                   ConnectingCaptionsCore)
#                                                   from this repo to iOS
#
# IOS_REPO overrides the App Store repo path (default ../connectingCaptions-iOS).
# Files listed in ALLOWED_DIFF are meant to differ: product copy, app paths,
# and the quality score, whose Pro copy reads Pro-only latency history.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
IOS_REPO=${IOS_REPO:-"$ROOT/../connectingCaptions-iOS"}
PRO_CORE="$ROOT/Sources/ConnectingCaptionsCore"
IOS_CORE="$IOS_REPO/Packages/ConnectingCaptionsCore/Sources/ConnectingCaptionsCore"
ALLOWED_DIFF="LiveTranslation/ConnectingCaptionsProduct.swift Persistence/AppSupportDirectory.swift LiveTranslation/TheaterQualityScore.swift"

[ -d "$IOS_CORE" ] || { echo "App Store core not found: $IOS_CORE (set IOS_REPO)"; exit 2; }
# The drift loop runs from inside PRO_CORE. A relative IOS_REPO would then
# point nowhere, every file would be skipped, and the check would pass.
IOS_CORE=$(CDPATH= cd -- "$IOS_CORE" && pwd)

if [ "${1:-}" = "--sync" ]; then
  shift
  [ "$#" -gt 0 ] || { echo "usage: $0 --sync PATH..."; exit 2; }
  for rel in "$@"; do
    [ -f "$PRO_CORE/$rel" ] || { echo "missing in this repo: $rel"; exit 2; }
    mkdir -p "$(dirname -- "$IOS_CORE/$rel")"
    cp "$PRO_CORE/$rel" "$IOS_CORE/$rel" && echo "synced $rel"
  done
  exit 0
fi

drift=0
cd "$PRO_CORE" || exit 2
for rel in $(find . -name '*.swift' | sed 's#^\./##' | sort); do
  [ -f "$IOS_CORE/$rel" ] || continue
  case " $ALLOWED_DIFF " in *" $rel "*) continue ;; esac
  if ! cmp -s "$rel" "$IOS_CORE/$rel"; then
    echo "DRIFT: $rel"
    drift=1
  fi
done
if [ "$drift" -ne 0 ]; then
  echo "Shared caption files differ. Reconcile, then: $0 --sync <path>"
  exit 1
fi
echo "Shared caption files match."
