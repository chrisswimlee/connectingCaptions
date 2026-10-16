"""Quality-review regressions use invented strings only, never claim app accuracy."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCORER = Path(__file__).with_name("score-theater-talk.py")
SPEC = importlib.util.spec_from_file_location("quality_scorer", SCORER)
scorer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(scorer)


class QualityReviewTests(unittest.TestCase):
    def run_score(self, rows, *flags):
        with tempfile.TemporaryDirectory() as folder:
            reference = Path(folder) / "reference.jsonl"
            reference.write_text("\n".join(json.dumps(row) for row in rows))
            report = Path(folder) / "quality.json"
            result = subprocess.run([sys.executable, str(SCORER), str(reference),
                                     "--json-output", str(report), *flags], capture_output=True, text=True)
            return result, json.loads(report.read_text()) if report.exists() else None

    def test_empty_hypothesis_counts_as_complete_omission(self):
        result, report = self.run_score([{"languageID": "en", "reference": "hello world", "hypothesis": ""}])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(report["groups"][0]["mean"], 1.0)

    def test_blank_human_reference_is_not_a_perfect_score(self):
        result, report = self.run_score([{"languageID": "en", "reference": "", "hypothesis": "hello"}])
        self.assertEqual(result.returncode, 1)
        self.assertIn("fill the human reference", result.stderr)
        self.assertIsNone(report)

    def test_unknown_legacy_language_requires_review(self):
        result, _ = self.run_score([{"languageID": "", "reference": "hello", "hypothesis": "hello"}])
        self.assertEqual(result.returncode, 1)
        self.assertIn("languageID", result.stderr)

    def test_asr_and_translation_are_reported_separately(self):
        result, report = self.run_score([
            {"kind": "asr", "languageID": "en", "reference": "hello", "hypothesis": "hello"},
            {"kind": "translation", "languageID": "ko", "reference": "안녕", "hypothesis": "안녕"},
        ])
        self.assertEqual(result.returncode, 0)
        self.assertEqual([(g["kind"], g["languageID"]) for g in report["groups"]], [("asr", "en"), ("translation", "ko")])

    def test_gate_cannot_double_count_bilingual_captions(self):
        rows = [{"kind": kind, "languageID": "en", "reference": "hello", "hypothesis": "hello"}
                for kind in ("asr", "translation") for _ in range(6)]
        result, report = self.run_score(rows, "--gate")
        self.assertEqual(result.returncode, 1)
        self.assertFalse(report["passes"])

    def test_gate_accepts_sufficient_reviewed_lines_per_group(self):
        rows = [{"kind": kind, "languageID": "en", "reference": "hello", "hypothesis": "hello"}
                for kind in ("asr", "translation") for _ in range(12)]
        result, report = self.run_score(rows, "--gate")
        self.assertEqual(result.returncode, 0)
        self.assertTrue(report["passes"])


if __name__ == "__main__":
    unittest.main()
