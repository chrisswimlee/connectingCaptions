#!/bin/bash
# Archive Connecting Captions Pro for iPhone and iPad and export an installable IPA.
#
# This is the direct-download build. It uses FluidVoice (FluidAudio Parakeet) and
# is not the App Store app. A person can install the IPA only on devices in the
# provisioning profile: development, ad hoc, or enterprise. iOS does not install
# an unsigned zip the way the Mac app does.
#
# Usage:
#   ./scripts/export-ios-pro.sh                  # development IPA
#   ./scripts/export-ios-pro.sh ad-hoc
#   ./scripts/export-ios-pro.sh enterprise
#
# Needs xcconfig/Local.xcconfig with DEVELOPMENT_TEAM, and a matching signing
# certificate. BUILD=42 sets the build number.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

METHOD="${1:-development}"
case "${METHOD}" in
    development|ad-hoc|enterprise) ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "Use development, ad-hoc, or enterprise." >&2; exit 2 ;;
esac

TEAM="$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' xcconfig/Local.xcconfig 2>/dev/null | tr -d '[:space:]')"
if [ -z "${TEAM}" ] || [ "${TEAM}" = "YOUR_TEAM_ID" ]; then
    echo "Set DEVELOPMENT_TEAM in xcconfig/Local.xcconfig first." >&2
    exit 1
fi

BUILD="${BUILD:-$(date +%Y%m%d%H%M)}"
OUT="${ROOT}/build/ios-pro-${BUILD}"
mkdir -p "${OUT}"
archive="${OUT}/ConnectingCaptionsProIOS.xcarchive"

cat > "${OUT}/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>${METHOD}</string>
    <key>teamID</key>
    <string>${TEAM}</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
EOF

echo "Archiving iOS Pro, build ${BUILD}, export ${METHOD}…"
xcodebuild archive \
    -project connectingCaptions.xcodeproj \
    -scheme ConnectingCaptionsProIOS \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "${archive}" \
    -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="${BUILD}"

xcodebuild -exportArchive \
    -archivePath "${archive}" \
    -exportPath "${OUT}" \
    -exportOptionsPlist "${OUT}/ExportOptions.plist" \
    -allowProvisioningUpdates

echo "IPA is in ${OUT}"
