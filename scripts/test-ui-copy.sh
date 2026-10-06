#!/usr/bin/env sh
# UI copy + accessibility drift gate.
#
# Fail-closed checks (regressions that break VoiceOver or the copy rules):
#   1. Banned marketing words inside Swift string literals (case-insensitive):
#      leverage, seamless, elevate, delve, effortlessly, game-changer,
#      cutting-edge, and "robust" before a data/content noun.
#   2. Text("") while accessibilityHidden(true) (or .accessibilityLabel(""))
#      on the same line: a VoiceOver trap - nothing to read AND skipped.
# Report-only (advisory, never blocks): em dash used with surrounding spaces
# inside string literals (style-guide rule 2).
#
# Exceptions live beside the code, not in an allowlist here: an inline
# `ui-copy-allowlist` comment on the same line exempts that line.
# Read-only script: greps sources, writes only temp files. Portable sh.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCAN_DIRS="$ROOT/Sources/ConnectingCaptions"
fail=0
warn=0
hits=$(mktemp) || exit 1
trap 'rm -f "$hits"' EXIT

for dir in $SCAN_DIRS; do
  [ -d "$dir" ] || { echo "CHECK DIR MISSING: $dir"; fail=1; }
done

# 1: Banned marketing words inside string literals.
: > "$hits"
for dir in $SCAN_DIRS; do
  [ -d "$dir" ] || continue
  grep -rn --include='*.swift' -E '"[^"]*([Ll]everage|[Ss]eamless|[Ee]levate|[Dd]elve|ffortlessly|[Gg]ame[- ]?[Cc]hanger|[Cc]utting-edge|[Rr]obust (data|content))' "$dir" >> "$hits" 2>/dev/null
done
if [ -s "$hits" ]; then
  while IFS= read -r line; do
    case "$line" in *ui-copy-allowlist*) continue ;; esac
    echo "BANNED COPY: $line"
    fail=1
  done < "$hits"
fi

# 2: empty-label + accessibilityHidden trap (fail-closed).
: > "$hits"
for dir in $SCAN_DIRS; do
  [ -d "$dir" ] || continue
  grep -rn --include='*.swift' -E 'Text\(""\).*accessibilityHidden\(true\)|accessibilityHidden\(true\).*Text\(""\)|\.accessibilityLabel\(""\)' "$dir" >> "$hits" 2>/dev/null
done
if [ -s "$hits" ]; then
  while IFS= read -r line; do
    case "$line" in *ui-copy-allowlist*) continue ;; esac
    echo "VOICEOVER TRAP (empty label + hidden): $line"
    fail=1
  done < "$hits"
fi

# 3 (report-only): em dash with surrounding spaces inside string literals.
: > "$hits"
for dir in $SCAN_DIRS; do
  [ -d "$dir" ] || continue
  grep -rn --include='*.swift' -E '"[^"]* — [^"]*"' "$dir" >> "$hits" 2>/dev/null
done
if [ -s "$hits" ]; then
  while IFS= read -r line; do
    warn=1
    echo "EM-DASH SPACING (advisory, style guide rule 2): $line"
  done < "$hits"
fi

if [ "$fail" -eq 0 ]; then
  if [ "$warn" -eq 1 ]; then
    echo "ui-copy + a11y sweep: fail-closed checks OK (em-dash reports above are advisory)"
  else
    echo "ui-copy + a11y sweep: OK"
  fi
fi
exit "$fail"
