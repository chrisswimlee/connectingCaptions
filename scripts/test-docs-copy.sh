#!/usr/bin/env sh
# Docs copy + link-health gate.
#
# Docs-only PRs skip the Swift build/lint pipeline entirely (see the paths
# filter in .github/workflows/build.yml), so without this, a markdown PR
# with a banned marketing word or a broken relative link ships with CI green
# and zero checks run. This job is deliberately cheap (ubuntu, no Xcode) so
# it doesn't push docs-only PRs onto the 20-minute macOS build.
#
# Fail-closed checks:
#   1. Banned marketing words (same list as scripts/test-ui-copy.sh), unless
#      the line also has an `ui-copy-allowlist` HTML comment.
#   2. Relative links (markdown `[text](path)`) that point at a file that
#      does not exist on disk, relative to the linking file's directory.
#      Anchors, mailto:, and http(s):// links are skipped.
# Read-only script: greps/stats files, writes only temp files. Portable sh.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fail=0
hits=$(mktemp) || exit 1
trap 'rm -f "$hits"' EXIT

docs=$(mktemp) || exit 1
trap 'rm -f "$hits" "$docs"' EXIT
find "$ROOT" -maxdepth 1 -name '*.md' > "$docs"
[ -d "$ROOT/docs" ] && find "$ROOT/docs" -name '*.md' >> "$docs"

if [ ! -s "$docs" ]; then
  echo "docs copy + link sweep: no markdown files found"
  exit 0
fi

# 1: Banned marketing words.
: > "$hits"
while IFS= read -r doc; do
  grep -n -E '([Ll]everage|[Ss]eamless|[Ee]levate|[Dd]elve|ffortlessly|[Gg]ame[- ]?[Cc]hanger|[Cc]utting-edge|[Rr]obust (data|content))' "$doc" |
    sed "s|^|$doc:|" >> "$hits"
done < "$docs"
if [ -s "$hits" ]; then
  while IFS= read -r line; do
    case "$line" in *ui-copy-allowlist*) continue ;; esac
    echo "BANNED COPY: $line"
    fail=1
  done < "$hits"
fi

# 2: Broken relative links.
: > "$hits"
while IFS= read -r doc; do
  docDir=$(dirname "$doc")
  grep -noE '\]\([^)[:space:]]+\)' "$doc" | while IFS= read -r match; do
    lineNum=$(printf '%s' "$match" | cut -d: -f1)
    target=$(printf '%s' "$match" | cut -d: -f2- | sed -e 's/^](//' -e 's/)$//')
    case "$target" in
      http://*|https://*|mailto:*|\#*) continue ;;
    esac
    target=$(printf '%s' "$target" | cut -d'#' -f1)
    [ -z "$target" ] && continue
    case "$target" in
      /*) resolved="$target" ;;
      *) resolved="$docDir/$target" ;;
    esac
    if [ ! -e "$resolved" ]; then
      echo "$doc:$lineNum:BROKEN LINK: $target" >> "$hits"
    fi
  done
done < "$docs"
if [ -s "$hits" ]; then
  while IFS= read -r line; do
    echo "$line"
    fail=1
  done < "$hits"
fi

if [ "$fail" -eq 0 ]; then
  echo "docs copy + link sweep: OK"
fi
exit "$fail"
