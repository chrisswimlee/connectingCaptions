#!/bin/bash
# Cut the next connectingCaptions version and publish it.
# GitHub Actions notarizes the zip and creates the Release. This script does
# not notarize on this Mac.
#
# Usage:
#   ./scripts/cut-release.sh              # next patch, then push v*
#   ./scripts/cut-release.sh 1.6.13       # this version
#   ./scripts/cut-release.sh --dry-run
#
# Write the notes under ## [Unreleased] in CHANGELOG.md first.
# The work tree must be clean, and main must match origin/main.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

DRY_RUN=0
REQUESTED=""

usage() {
    cat <<'EOF'
Usage: ./scripts/cut-release.sh [--dry-run] [X.Y.Z]

Cuts the next patch, or X.Y.Z, commits it, and pushes a v* tag to origin.
.github/workflows/release.yml then signs, notarizes, and publishes the zip.

Write the user-facing notes under ## [Unreleased] in CHANGELOG.md first.
The work tree must be clean, and main must match origin/main.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)
            if [ -n "${REQUESTED}" ]; then
                echo "Only one version argument is allowed." >&2
                exit 2
            fi
            REQUESTED="$1"
            shift
            ;;
    esac
done

if ! command -v gh >/dev/null 2>&1; then
    echo "gh is required. Install GitHub CLI and run gh auth login." >&2
    exit 1
fi

origin_url="$(git remote get-url origin)"
case "${origin_url}" in
    *chrisswimlee/connectingCaptions*) ;;
    *)
        echo "origin is ${origin_url}." >&2
        echo "This script only pushes chrisswimlee/connectingCaptions." >&2
        exit 1
        ;;
esac

branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "${branch}" != "main" ]; then
    echo "Cut releases from main. This checkout is ${branch}." >&2
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "The work tree is not clean. Commit or stash before cutting a release." >&2
    git status --short >&2
    exit 1
fi

git fetch origin main --tags
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    echo "main does not match origin/main. Push or pull before cutting a release." >&2
    exit 1
fi

current="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)"
if ! [[ "${current}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "CFBundleShortVersionString is ${current}, not X.Y.Z." >&2
    exit 1
fi
if ! [[ "${build}" =~ ^[0-9]+$ ]]; then
    echo "CFBundleVersion is ${build}, not a number." >&2
    exit 1
fi

if [ -n "${REQUESTED}" ]; then
    version="${REQUESTED}"
    if ! [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Version must look like 1.6.13." >&2
        exit 2
    fi
else
    major="${current%%.*}"
    rest="${current#*.}"
    minor="${rest%%.*}"
    patch="${rest#*.}"
    version="${major}.${minor}.$((patch + 1))"
fi

next_build="$((build + 1))"
tag="v${version}"

if ! python3 - "${current}" "${version}" <<'PY'
import sys
current = tuple(map(int, sys.argv[1].split(".")))
requested = tuple(map(int, sys.argv[2].split(".")))
raise SystemExit(0 if requested > current else 1)
PY
then
    echo "Version ${version} must be newer than ${current}." >&2
    exit 1
fi

if git rev-parse --verify --quiet "refs/tags/${tag}" >/dev/null; then
    echo "${tag} already exists locally." >&2
    exit 1
fi
if git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1; then
    echo "${tag} is already on origin." >&2
    exit 1
fi

notes="$(python3 - "${version}" <<'PY'
import re, sys
from pathlib import Path
version = sys.argv[1]
text = Path("CHANGELOG.md").read_text(encoding="utf-8")
match = re.search(r"^## \[Unreleased\]\n(.*?)(?=^## )", text, re.M | re.S)
if match is None:
    sys.exit(3)
body = match.group(1).strip()
if not body:
    sys.exit(4)
if f"## [{version}]" in text:
    sys.exit(5)
print(body)
PY
)" || {
    status=$?
    if [ "${status}" -eq 4 ]; then
        echo "CHANGELOG.md has no notes under ## [Unreleased]." >&2
        echo "Add the user-facing bullets, then rerun this script." >&2
    elif [ "${status}" -eq 5 ]; then
        echo "CHANGELOG.md already has [${version}]." >&2
    else
        echo "Could not read the Unreleased changelog section." >&2
    fi
    exit 1
}

echo "Cut ${current} (${build}) → ${version} (${next_build}), tag ${tag}"
if [ "${DRY_RUN}" -eq 1 ]; then
    echo "Dry run. No files changed and nothing pushed."
    exit 0
fi

python3 - "${version}" "${next_build}" "$(date +%Y-%m-%d)" <<'PY'
import re, sys
from pathlib import Path

version, build, day = sys.argv[1:4]

changelog = Path("CHANGELOG.md")
text = changelog.read_text(encoding="utf-8")
match = re.search(r"^## \[Unreleased\]\n(.*?)(?=^## )", text, re.M | re.S)
if match is None:
    raise SystemExit("CHANGELOG.md has no Unreleased section")
body = match.group(1).strip()
replacement = f"## [Unreleased]\n\n## [{version}] — {day}\n\n{body}\n\n"
changelog.write_text(text[: match.start()] + replacement + text[match.end() :], encoding="utf-8")

readme = Path("README.md")
readme_text = readme.read_text(encoding="utf-8")
if "releases/latest/download/Connecting-Captions.zip" not in readme_text:
    raise SystemExit("README.md download link must stay on the latest Connecting-Captions.zip")

project = Path("connectingCaptions.xcodeproj/project.pbxproj")
project_text = project.read_text(encoding="utf-8")
marketing, marketing_count = re.subn(
    r"MARKETING_VERSION = [0-9.]+;",
    f"MARKETING_VERSION = {version};",
    project_text,
)
build_text, build_count = re.subn(
    r"CURRENT_PROJECT_VERSION = [0-9]+;",
    f"CURRENT_PROJECT_VERSION = {build};",
    marketing,
)
if marketing_count != 2 or build_count != 2:
    raise SystemExit(
        f"Expected 2 MARKETING_VERSION and 2 CURRENT_PROJECT_VERSION edits, "
        f"got {marketing_count} and {build_count}"
    )
project.write_text(build_text, encoding="utf-8")
PY

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version}" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${next_build}" Info.plist

git add Info.plist connectingCaptions.xcodeproj/project.pbxproj CHANGELOG.md README.md
git commit -m "$(cat <<EOF
Cut ${version} for the notarized release.

EOF
)"

git tag "${tag}"
git push --atomic origin HEAD:main "refs/tags/${tag}"

echo "Waiting for GitHub Actions to notarize ${tag}..."
run_id=""
for _ in $(seq 1 30); do
    run_id="$(gh run list --repo chrisswimlee/connectingCaptions --workflow release.yml --limit 20 \
        --json databaseId,headBranch \
        --jq "[.[] | select(.headBranch==\"${tag}\")][0].databaseId // empty")"
    if [ -n "${run_id}" ]; then
        break
    fi
    sleep 10
done
if [ -z "${run_id}" ]; then
    echo "The release workflow for ${tag} did not appear." >&2
    echo "https://github.com/chrisswimlee/connectingCaptions/actions/workflows/release.yml" >&2
    exit 1
fi

gh run watch "${run_id}" --repo chrisswimlee/connectingCaptions --exit-status

notes_file="$(mktemp)"
{
    cat <<EOF
macOS 15 or later, Apple Silicon. The zip is notarized.

1. Download [Connecting-Captions-${version}.zip](https://github.com/chrisswimlee/connectingCaptions/releases/download/${tag}/Connecting-Captions-${version}.zip).
2. Unzip it and drag **Connecting Captions** to Applications.
3. Open Theater, allow the microphone, then press **Listen**.

**Homebrew**

\`\`\`bash
brew tap chrisswimlee/connectingcaptions
brew trust chrisswimlee/connectingcaptions
brew install --cask connectingcaptions
\`\`\`

Personal use stays free. If IT or legal need a named license or an SLA, [request a commercial license](https://chrisswimlee.com/connectingCaptions/license/).

- [Product page](https://chrisswimlee.com/connectingCaptions)
- [Homebrew tap](https://github.com/chrisswimlee/homebrew-connectingcaptions)

## What's in ${version}

EOF
    python3 scripts/extract-changelog.py "${tag}"
} > "${notes_file}"

gh release edit "${tag}" --repo chrisswimlee/connectingCaptions --notes-file "${notes_file}"
rm -f "${notes_file}"

echo "Notarized release: https://github.com/chrisswimlee/connectingCaptions/releases/tag/${tag}"
echo "The Homebrew tap still serves the previous zip until you update that cask."
