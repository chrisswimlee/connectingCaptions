#!/bin/bash
# Build an install package for Jamf or Fleet.
# The pkg is unsigned. Sign it with a Developer ID Installer certificate before you ship it.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  ./scripts/build-mdm-pkg.sh --app dist/fluidSubtitles.app --output dist/fluidSubtitles-mdm.pkg
  ./scripts/build-mdm-pkg.sh --app dist/fluidSubtitles.app --license ./license.key \
      --roster ./seats.roster --settings ./settings.fleet.json --output dist/fluidSubtitles-mdm.pkg

Installs the app in /Applications and, when given, these root-owned files:
  /Library/Application Support/fluidSubtitles/license.key
  /Library/Application Support/fluidSubtitles/seats.roster
  /Library/Application Support/fluidSubtitles/settings.fleet.json

Optional: --version 1.2.3 (default: CFBundleShortVersionString, or 0)
          --identifier com.fluidsubtitles.mdm
          --dry-run   print the staged payload and skip pkgbuild
EOF
}

APP=""
LICENSE=""
ROSTER=""
SETTINGS=""
OUTPUT=""
VERSION=""
IDENTIFIER="com.fluidsubtitles.mdm"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app) APP="${2:-}"; shift 2 ;;
        --license) LICENSE="${2:-}"; shift 2 ;;
        --roster) ROSTER="${2:-}"; shift 2 ;;
        --settings) SETTINGS="${2:-}"; shift 2 ;;
        --output) OUTPUT="${2:-}"; shift 2 ;;
        --version) VERSION="${2:-}"; shift 2 ;;
        --identifier) IDENTIFIER="${2:-}"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [[ -z "${APP}" || ! -d "${APP}" ]]; then
    echo "Need --app pointing at a .app bundle." >&2
    exit 1
fi
if [[ "${DRY_RUN}" -eq 0 && -z "${OUTPUT}" ]]; then
    echo "Need --output, or pass --dry-run." >&2
    exit 1
fi

for extra in "${LICENSE}" "${ROSTER}" "${SETTINGS}"; do
    if [[ -n "${extra}" && ! -f "${extra}" ]]; then
        echo "File not found: ${extra}" >&2
        exit 1
    fi
done

if [[ -z "${VERSION}" ]]; then
    plist="${APP}/Contents/Info.plist"
    if [[ -f "${plist}" ]]; then
        VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${plist}" 2>/dev/null || true)"
    fi
    VERSION="${VERSION:-0}"
fi

STAGE="$(mktemp -d)"
cleanup() { rm -rf "${STAGE}"; }
trap cleanup EXIT

APP_NAME="$(basename "${APP}")"
mkdir -p "${STAGE}/Applications"
cp -R "${APP}" "${STAGE}/Applications/${APP_NAME}"

MANAGED="${STAGE}/Library/Application Support/fluidSubtitles"
mkdir -p "${MANAGED}"
[[ -n "${LICENSE}" ]] && cp "${LICENSE}" "${MANAGED}/license.key"
[[ -n "${ROSTER}" ]] && cp "${ROSTER}" "${MANAGED}/seats.roster"
[[ -n "${SETTINGS}" ]] && cp "${SETTINGS}" "${MANAGED}/settings.fleet.json"

echo "identifier ${IDENTIFIER}"
echo "version ${VERSION}"
echo "app /Applications/${APP_NAME}"
if [[ -f "${MANAGED}/license.key" ]]; then echo "managed license.key"; fi
if [[ -f "${MANAGED}/seats.roster" ]]; then echo "managed seats.roster"; fi
if [[ -f "${MANAGED}/settings.fleet.json" ]]; then echo "managed settings.fleet.json"; fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
    exit 0
fi

mkdir -p "$(dirname "${OUTPUT}")"
pkgbuild \
    --root "${STAGE}" \
    --identifier "${IDENTIFIER}" \
    --version "${VERSION}" \
    --install-location "/" \
    --output "${OUTPUT}"
echo "Wrote ${OUTPUT}"
