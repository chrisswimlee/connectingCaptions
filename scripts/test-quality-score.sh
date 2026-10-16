#!/bin/sh
# Keeps the two Theater scorers counting the same units.
#
# Why this exists (2026-10-14 audit):
# There are two implementations of the same WER/CER math — TheaterQualityScore.swift
# (what the app uses to decide whether a line is good enough to print) and
# scripts/score-theater-talk.py (what you run over a recorded talk). They had no
# shared definition of "one unit". Swift walked *grapheme clusters* and then dropped
# anything that was not a letter or a number; Python iterated *code points* with
# isalnum(). For Thai, whose vowels and tones are combining marks stacked on a base
# consonant, that meant two things at once: marks were invisible to both, and the two
# scorers could disagree about the same line. `ครับ` and `ครั๊บ` — different
# sentences — scored a perfect 0.0.
#
# What it checks:
# 1. the pinned vectors in Tests/ConnectingCaptionsIntegrationTests/Fixtures/
#    quality-vectors.jsonl still reproduce exactly, which means the Python scorer
#    still means what the Swift scorer means;
# 2. the pinned file still has the number of entries the Swift unit test asserts on,
#    so the file cannot be quietly truncated to make a test green.
#
# This is a scorer self-test, not a quality measurement. A green run here says the
# ruler is honest. It says nothing about whether the app is good at subtitling
# anything — that needs a reference JSONL from a real talk. See docs/STAGE_SCORE.md.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

vectors="$repo_root/Tests/ConnectingCaptionsIntegrationTests/Fixtures/quality-vectors.jsonl"
scorer="$repo_root/scripts/score-theater-talk.py"

if [ ! -f "$vectors" ]; then
    echo "Missing $vectors. The scorer has no pinned expectations to check itself against."
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found; cannot verify the scorer."
    exit 1
fi

echo "Scorer vectors: $vectors"
python3 "$scorer" --check-vectors

# A truncated fixture is the failure mode that hides the other one: the Swift test
# asserts on the entry count, so a shorter file has to fail here too.
count=$(grep -c '^{' "$vectors")
if [ "$count" -lt 19 ]; then
    echo "Expected at least 19 pinned vectors, found $count."
    exit 1
fi
echo "Pinned vector count: $count"

# The 0% case: a reference and a hypothesis that differ only in a Thai tone mark
# must NOT score as a perfect match. Pinned as a command-line check so it fails
# even on a machine that skipped the Swift test target.
python3 - "$scorer" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("scorer", sys.argv[1])
scorer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scorer)

# ครับ vs ครั๊บ — the second carries mai ek. Different words, not a typo.
rate = scorer.error_rate("ครับ", "ครั๊บ", "th")
if rate <= 0.0:
    print(f"Thai tone mark invisible to the scorer (rate={rate}). A caption that "
          "changes the tone now scores as a perfect transcription, which is the "
          "blind spot this check was written to keep closed.")
    sys.exit(1)
print(f"Thai tone mark visible: rate={rate:.4f}")
PY

echo "Scorer self-check: OK"

# Armed automatically the day a real reference JSONL is checked in. Until then this
# is a no-op, and that is deliberate: a gate that fails forever gets switched off,
# and a gate that never runs proves nothing.
reference="$repo_root/docs/samples/reference.jsonl"
if [ -f "$reference" ]; then
    echo
    echo "Scoring the recorded talk: $reference"
    python3 "$scorer" --gate "$reference"
    echo "Reference corpus scored."
fi
