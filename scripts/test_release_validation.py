"""A green unit suite must never silently stand in for a human release review."""
import importlib.util
import contextlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("release_validation", Path(__file__).with_name("validate-release.py"))
validation = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validation)


class ReleaseEvidenceTests(unittest.TestCase):
    def evidence(self):
        return {"sourceFingerprint": "current", "reviewer": "Test fixture reviewer",
                "checks": {key: {"status": "passed", "notes": "Invented evidence for gate unit testing only"}
                           for key in validation.MANUAL_CHECKS}}

    def test_missing_live_checks_are_not_ready(self):
        self.assertFalse(validation.manual_complete({}, "current"))
        evidence = self.evidence()
        evidence["checks"]["recorded_demo"]["status"] = "pending"
        self.assertFalse(validation.manual_complete(evidence, "current"))

    def test_review_must_apply_to_the_current_source(self):
        self.assertFalse(validation.manual_complete(self.evidence(), "changed"))

    def test_review_requires_a_named_reviewer_and_notes(self):
        evidence = self.evidence()
        evidence["reviewer"] = ""
        self.assertFalse(validation.manual_complete(evidence, "current"))
        evidence = self.evidence()
        evidence["checks"]["ime_delivery"]["notes"] = ""
        self.assertFalse(validation.manual_complete(evidence, "current"))

    def test_complete_current_review_is_accepted(self):
        self.assertTrue(validation.manual_complete(self.evidence(), "current"))

    def test_malformed_review_is_rejected(self):
        for evidence in (None, [], {"sourceFingerprint": "current", "reviewer": "Tester", "checks": []}):
            with self.subTest(evidence=evidence):
                self.assertFalse(validation.manual_complete(evidence, "current"))
        evidence = self.evidence()
        evidence["checks"]["ime_delivery"]["notes"] = 123
        self.assertFalse(validation.manual_complete(evidence, "current"))

    def test_fingerprint_includes_build_and_distribution_inputs(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            files = ("Sources/App.swift", "Tests/AppTests.swift", "scripts/validate-release.py",
                     "connectingCaptions.xcodeproj/project.pbxproj", ".github/workflows/release.yml",
                     "Info.plist", "connectingCaptions.entitlements", "Package.swift", "Package.resolved",
                     "build.sh", ".swiftlint.yml", "xcconfig/Shared.xcconfig")
            for name in files:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("original")
            original = validation.fingerprint(root)
            for name in files:
                with self.subTest(name=name):
                    path = root / name
                    path.write_text("changed")
                    self.assertNotEqual(validation.fingerprint(root), original)
                    path.write_text("original")
            (root / "xcconfig/Local.xcconfig").write_text("local signing settings")
            self.assertEqual(validation.fingerprint(root), original)

    def run_validation(self, fingerprints, *flags):
        import json
        with tempfile.TemporaryDirectory() as folder:
            with patch.object(validation, "fingerprint", side_effect=fingerprints), \
                    patch.object(validation.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as run, \
                    patch("sys.argv", ["validate-release.py", "--output", folder, *flags]), \
                    contextlib.redirect_stdout(io.StringIO()):
                status = validation.main()
            return status, json.loads(Path(folder, "summary.json").read_text()), run.call_args_list

    def test_automatic_validation_builds_release_but_still_requires_live_evidence(self):
        status, report, commands = self.run_validation(["current", "current"], "--require-ready")
        self.assertEqual(status, 1)
        self.assertTrue(report["automaticPassed"])
        self.assertFalse(report["releaseReady"])
        release = next(row for row in report["checks"] if row["name"] == "release-build")
        self.assertEqual(release["status"], "passed")
        self.assertTrue(any("Release" in call.args[0] for call in commands))
        bundle = next(row for row in report["checks"] if row["name"] == "release-bundle")
        self.assertEqual(bundle["status"], "passed")
        self.assertTrue(any(call.args[0] == ["bash", "build.sh", "verify-bundle"] for call in commands))

    def test_changed_inputs_cannot_produce_a_passing_automatic_result(self):
        status, report, _ = self.run_validation(["before", "after"])
        self.assertEqual(status, 1)
        self.assertFalse(report["sourceUnchanged"])
        self.assertFalse(report["automaticPassed"])


if __name__ == "__main__":
    unittest.main()
