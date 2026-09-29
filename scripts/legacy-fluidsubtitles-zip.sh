#!/bin/bash
# fluidSubtitles 1.6.12 looks up fluidsubtitles-{version}.zip, then rejects any app
# whose codesign identifier is not com.fluidsubtitles.app. Copying the Connecting
# Captions zip under that name fails that check. Re-sign a copy as the old identifier.
set -euo pipefail

source_app="${1:?path to Connecting Captions.app}"
dest_zip="${2:?path to fluidsubtitles-version.zip}"
legacy_id="com.fluidsubtitles.app"

if [ ! -d "${source_app}" ]; then
  echo "App not found at ${source_app}" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
copy="${work}/$(basename "${source_app}")"
ditto "${source_app}" "${copy}"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${legacy_id}" "${copy}/Contents/Info.plist"

authority="$(codesign -dvvv "${source_app}" 2>&1 | sed -n 's/^Authority=Developer ID Application: //p' | head -n 1)"
if [ -z "${authority}" ]; then
  echo "The source app has no Developer ID Application signature." >&2
  exit 1
fi

identity="${CONNECTINGCAPTIONS_CODESIGN_IDENTITY:-}"
if [ -z "${identity}" ]; then
  identity="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application: ${authority}" \
    | awk '{ print $2 }' \
    | tail -n 1)"
fi
if [ -z "${identity}" ]; then
  echo "No Developer ID identity for ${authority}." >&2
  exit 1
fi

entitlements="$(cd "$(dirname "$0")/.." && pwd)/connectingCaptions.entitlements"
if [ ! -f "${entitlements}" ]; then
  echo "Missing entitlements at ${entitlements}." >&2
  exit 1
fi
if ! codesign --force --sign "${identity}" --timestamp --options runtime \
  --entitlements "${entitlements}" \
  "${copy}"
then
  echo "Retrying the signature. The timestamp server did not answer." >&2
  codesign --force --sign "${identity}" --timestamp --options runtime \
    --entitlements "${entitlements}" \
    "${copy}"
fi
codesign --verify --deep --strict "${copy}"

identifier="$(codesign -dv "${copy}" 2>&1 | sed -n 's/^Identifier=//p')"
if [ "${identifier}" != "${legacy_id}" ]; then
  echo "Expected identifier ${legacy_id}, got ${identifier}." >&2
  exit 1
fi
requirements="$(codesign -d --requirements - "${copy}" 2>&1 || true)"
if ! printf '%s\n' "${requirements}" | grep -F "identifier \"${legacy_id}\"" >/dev/null; then
  echo "Designated requirement does not name ${legacy_id}." >&2
  exit 1
fi

if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]; then
  notarize_zip="${work}/notarize.zip"
  ditto -c -k --keepParent "${copy}" "${notarize_zip}"
  xcrun notarytool submit "${notarize_zip}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APPLE_APP_SPECIFIC_PASSWORD}" \
    --wait
  xcrun stapler staple "${copy}"
elif [ "${REQUIRE_NOTARIZATION:-}" = "1" ]; then
  echo "APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_SPECIFIC_PASSWORD are required for the fluidSubtitles update." >&2
  exit 1
fi

mkdir -p "$(dirname "${dest_zip}")"
rm -f "${dest_zip}"
ditto -c -k --keepParent "${copy}" "${dest_zip}"
echo "Legacy update zip: ${dest_zip}"
