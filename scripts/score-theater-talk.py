#!/usr/bin/env python3
"""Score a Theater talk against a reference JSONL. Same 15% bar as TheaterQualityScore.

Each line is one JSON object: languageID, reference, hypothesis.
See docs/STAGE_SCORE.md for an English, Korean, and Japanese layout example.
Check in LastListenLatency.json from a real Mac. Do not invent WER.

Two modes beyond the plain score:

  --check-vectors   Re-derive every pinned vector in
                    Tests/ConnectingCaptionsIntegrationTests/Fixtures/
                    quality-vectors.jsonl and fail on any that moved. That file
                    is the contract between this script and the Swift scorer;
                    a silent change here means every quoted WER/CER was measured
                    with a different ruler than the runtime used.
  --gate            Treat a missing or short reference file as a failure instead
                    of printing a confident number for four hand-written lines.
"""

from __future__ import annotations

import json
import argparse
import re
import sys
import unicodedata
from pathlib import Path


STAGE_ACCEPTABLE = 0.15
COMPACT = {"ko", "th", "ja", "zh"}
SUPPORTED_LANGUAGES = {"en", "ko", "ja", "th", "ar", "zh", "nl", "fr", "de", "hi", "id", "it", "pl", "pt", "ru", "es", "tr", "uk", "vi"}

# Unicode general categories that carry a letter's identity. Mirrors
# `compareCategories` in TheaterQualityScore.swift — Thai stacks its vowels and
# tones as Mn marks on a base consonant, and a scorer that drops them scores
# `ครับ` and `ครั๊บ` as a perfect match. Keep the two lists in step.
KEEP_CATEGORIES = {"Lu", "Ll", "Lt", "Lm", "Lo", "Nd", "Nl", "No", "Mn", "Mc", "Me"}

# A reference file shorter than this proves nothing about a whole talk.
MIN_GATE_LINES = 12


def language_code(language_id: str) -> str:
    return (language_id or "en").split("-")[0].lower()


def tokens(text: str) -> list[str]:
    return [part for part in re.split(r"[\s\W]+", text.lower()) if part]


def folded_letters(text: str) -> list[str]:
    """Units for a compact script: one per Unicode scalar, marks kept.

    Mirrors `compactUnits` in TheaterQualityScore.swift, which walks
    `.unicodeScalars`. A Python str iterates code points, which is the same
    sequence, so no normalisation step is wanted here: `text.lower()` then a
    category filter already matches the runtime.

    Do not add an NFD step back. Thai vowels and tones already arrive as
    separate scalars, so decomposition fixes nothing; it only splits every
    Korean syllable block into three jamo and halves a number that was already
    correct (`안녕` vs `안녕하세요` moves from 1.5 to 1.0). The bug this
    function used to have was `character.isalnum()`, which is False for the
    Thai marks and threw them away.
    """
    return [character for character in text.lower() if unicodedata.category(character) in KEEP_CATEGORIES]


def edit_distance(left: list[str], right: list[str]) -> int:
    if not left:
        return len(right)
    if not right:
        return len(left)
    previous = list(range(len(right) + 1))
    current = [0] * (len(right) + 1)
    for i, left_item in enumerate(left):
        current[0] = i + 1
        for j, right_item in enumerate(right):
            cost = 0 if left_item == right_item else 1
            current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + cost)
        previous, current = current, previous
    return previous[len(right)]


def error_rate(reference: str, hypothesis: str, language_id: str) -> float:
    if language_code(language_id) in COMPACT:
        left = folded_letters(reference)
        right = folded_letters(hypothesis)
    else:
        left = tokens(reference)
        right = tokens(hypothesis)
    if not left:
        return 0.0 if not right else 1.0
    # Unbounded above 1.0 by design: a hypothesis that invents material scores
    # over 1.0, which is how a real WER behaves too. Do not clamp it — clamping
    # would make the mean look comparable to a published figure when it is not.
    return edit_distance(left, right) / len(left)


def load_lines(path: Path) -> list[dict]:
    rows = []
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        row = json.loads(line)
        if not isinstance(row, dict) or not isinstance(row.get("reference"), str) or not row["reference"].strip():
            raise ValueError(f"{path}:{number}: fill the human reference before scoring")
        if not isinstance(row.get("hypothesis"), str):
            raise ValueError(f"{path}:{number}: hypothesis must be text (empty text counts as a missed caption)")
        if not isinstance(row.get("kind", "asr"), str) or row.get("kind", "asr") not in {"asr", "translation"}:
            raise ValueError(f"{path}:{number}: kind must be asr or translation")
        language_id = row.get("languageID", row.get("language_id", "en"))
        if not isinstance(language_id, str) or language_code(language_id) not in SUPPORTED_LANGUAGES or not language_id.strip():
            raise ValueError(f"{path}:{number}: set the reference languageID")
        rows.append(row)
    return rows


def check_vectors(path: Path) -> int:
    """Fail if this script no longer reproduces the pinned vectors."""
    drift = []
    total = 0
    for raw in path.read_text(encoding="utf-8").splitlines():
        if not raw.strip():
            continue
        total += 1
        row = json.loads(raw)
        got = error_rate(row["reference"], row["hypothesis"], row.get("languageID") or "en")
        if abs(got - row["expected"]) > 1e-6:
            drift.append((row["id"], row["expected"], got))
    for vector_id, pinned, got in drift:
        print(f"DRIFT  {vector_id}: pinned={pinned:.6f}  this script={got:.6f}", file=sys.stderr)
    if drift:
        print(
            f"\n{len(drift)} of {total} vectors moved. The scorer and its pinned "
            "expectations no longer agree, so no number produced by either side "
            "is trustworthy. Fix the scorer or re-pin deliberately.",
            file=sys.stderr,
        )
        return 1
    print(f"scorer reproduces all {total} pinned vectors")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", nargs="?", type=Path)
    parser.add_argument("latency", nargs="?", type=Path)
    parser.add_argument("--check-vectors", action="store_true")
    parser.add_argument("--gate", action="store_true")
    parser.add_argument("--json-output", type=Path, help="Write per-kind, per-language results for release evidence")
    args = parser.parse_args()
    vectors = Path(__file__).resolve().parent.parent / (
        "Tests/ConnectingCaptionsIntegrationTests/Fixtures/quality-vectors.jsonl"
    )
    if args.check_vectors:
        if not vectors.is_file():
            print(f"missing {vectors}", file=sys.stderr)
            return 1
        return check_vectors(vectors)

    if args.reference is None:
        parser.error("provide reference.jsonl or --check-vectors")

    path = args.reference
    if not path.is_file():
        print(f"{path} does not exist. There is nothing to score.", file=sys.stderr)
        return 1
    try:
        rows = load_lines(path)
    except (ValueError, OSError) as error:
        print(error, file=sys.stderr)
        return 1
    if args.gate and len(rows) < MIN_GATE_LINES:
        print(
            f"{len(rows)} lines is not a talk. Need at least {MIN_GATE_LINES} "
            "before a mean means anything.",
            file=sys.stderr,
        )
        return 1
    if not rows:
        print("no lines", file=sys.stderr)
        return 1

    errors = []
    groups = {}
    shown = True
    for row in rows:
        language_id = row.get("languageID") or row.get("language_id") or "en"
        rate = error_rate(row["reference"], row["hypothesis"], language_id)
        errors.append(rate)
        group = (row.get("kind", "asr"), language_code(language_id))
        groups.setdefault(group, []).append(rate)
        if rate > STAGE_ACCEPTABLE:
            shown = False
        print(f"{rate:.3f}  {language_id}  {row['reference'][:48]}")
    mean = sum(errors) / len(errors)
    print(f"mean={mean:.3f} would_show={str(shown).lower()} lines={len(errors)}")
    summaries = []
    for (kind, language_id), rates in sorted(groups.items()):
        passed = all(rate <= STAGE_ACCEPTABLE for rate in rates)
        enough = not args.gate or len(rates) >= MIN_GATE_LINES
        shown = shown and enough
        summaries.append({"kind": kind, "languageID": language_id, "lines": len(rates),
                          "mean": sum(rates) / len(rates), "passes": passed and enough})
        print(f"{kind}/{language_id} mean={sum(rates) / len(rates):.3f} lines={len(rates)} passes={passed and enough}")
        if not enough:
            print(f"Need at least {MIN_GATE_LINES} human-reviewed lines per kind and language.", file=sys.stderr)
    if args.latency:
        latency = json.loads(args.latency.read_text(encoding="utf-8"))
        print(
            "latency "
            f"e2e={latency.get('endToEndMilliseconds')} "
            f"mt={latency.get('machineTranslationMilliseconds')}"
        )
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json.dumps({"reference": str(path), "passes": shown,
                                               "groups": summaries}, indent=2) + "\n", encoding="utf-8")
    return 0 if shown else 1


if __name__ == "__main__":
    raise SystemExit(main())
