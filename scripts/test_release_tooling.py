"""Release tooling must fail before packaging when metadata or signing is missing."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class ChangelogTests(unittest.TestCase):
    def extract(self, version, text):
        with tempfile.TemporaryDirectory() as folder:
            Path(folder, "CHANGELOG.md").write_text(text)
            return subprocess.run([sys.executable, str(ROOT / "scripts/extract-changelog.py"), version],
                                  cwd=folder, capture_output=True, text=True)

    def test_missing_release_cannot_use_unreleased_notes(self):
        result = self.extract("v2.0.0", "## [Unreleased]\n\nFuture notes\n\n## [1.0.0]\n\nOld notes\n")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("no notes for [2.0.0]", result.stderr)

    def test_exact_version_preserves_subheadings_and_stops_at_next_release(self):
        result = self.extract("v2.0.0", "## [Unreleased]\n\nFuture\n\n## [2.0.0] — 2026-10-15\n\n"
                              "### Fixed\n\nRelease notes\n\n## [1.0.0]\n\nOld\n")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "### Fixed\n\nRelease notes")

    def test_empty_exact_release_fails_even_with_unreleased_notes(self):
        result = self.extract("2.0.0", "## [Unreleased]\n\nFuture\n\n## [2.0.0]\n\n## [1.0.0]\n\nOld\n")
        self.assertEqual(result.returncode, 1)


class ReleaseSigningTests(unittest.TestCase):
    def run_build(self, identity="", discovered="", legacy_identity=""):
        with tempfile.TemporaryDirectory() as folder:
            for name, script in {
                "security": '#!/bin/sh\nprintf "%s\\n" "$TEST_IDENTITIES"\n',
                "xcodebuild": '#!/bin/sh\necho "TEST: xcodebuild invoked"\nexit 73\n',
            }.items():
                executable = Path(folder, name)
                executable.write_text(script)
                executable.chmod(0o755)
            env = dict(os.environ, PATH=folder + os.pathsep + os.environ.get("PATH", ""),
                       CONNECTINGCAPTIONS_DEVELOPMENT_TEAM="TESTTEAM00",
                       CONNECTINGCAPTIONS_CODESIGN_IDENTITY=identity,
                       FLUIDSUBTITLES_CODESIGN_IDENTITY=legacy_identity, TEST_IDENTITIES=discovered)
            return subprocess.run(["bash", str(ROOT / "build.sh"), "release"], env=env,
                                  capture_output=True, text=True)

    def test_explicit_identity_is_honored_without_discovery(self):
        for identity in ("A" * 40, "Developer ID Application: Test Fixture (TESTTEAM00)"):
            with self.subTest(identity=identity):
                result = self.run_build(identity=identity)
                self.assertEqual(result.returncode, 73)
                self.assertIn(f"Developer ID identity: {identity}", result.stdout)

    def test_explicit_identity_wins_over_discovered_certificate(self):
        result = self.run_build(identity="A" * 40,
                                discovered='1) BBBB "Developer ID Application: Other (TESTTEAM00)"')
        self.assertEqual(result.returncode, 73)
        self.assertIn("Developer ID identity: " + "A" * 40, result.stdout)

    def test_legacy_identity_is_still_supported(self):
        result = self.run_build(legacy_identity="C" * 40)
        self.assertEqual(result.returncode, 73)
        self.assertIn("Developer ID identity: " + "C" * 40, result.stdout)

    def test_discovery_is_used_without_override(self):
        result = self.run_build(discovered='1) DDDD "Developer ID Application: Fixture (TESTTEAM00)"')
        self.assertEqual(result.returncode, 73)
        self.assertIn("Developer ID identity: DDDD", result.stdout)

    def test_missing_identity_fails_with_actionable_message_before_build(self):
        result = self.run_build()
        self.assertEqual(result.returncode, 1)
        self.assertIn("No Developer ID Application identity", result.stderr)
        self.assertNotIn("TEST: xcodebuild invoked", result.stdout)


class ReleaseBundleTests(unittest.TestCase):
    def bundle_check(self, *, missing_app=False, incomplete=False, verify_status=0):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            derived = root / "DerivedData"
            app = derived / "Build/Products/Release/Fixture.app"
            framework = app / "Contents/Frameworks/CTranscribe.framework"
            if not missing_app:
                (framework / "Versions/A/Resources").mkdir(parents=True)
                (framework / "Versions/A/CTranscribe").write_text("versioned binary")
                if not incomplete:
                    (framework / "Versions/A/Resources/Info.plist").write_text("framework metadata")
                (framework / "Versions/Current").mkdir()
                (framework / "Resources").mkdir()
                (framework / "CTranscribe").write_text("flattened binary")
            log = root / "sign.log"
            binary = root / "codesign"
            binary.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$TEST_SIGN_LOG"\n'
                              'if [ "$1" = --verify ]; then exit "$TEST_VERIFY_STATUS"; fi\n')
            binary.chmod(0o755)
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ.get("PATH", ""),
                       CONNECTINGCAPTIONS_DERIVED_DATA_PATH=str(derived),
                       CONNECTINGCAPTIONS_RELEASE_APP_BUNDLE_NAME="Fixture.app",
                       TEST_SIGN_LOG=str(log), TEST_VERIFY_STATUS=str(verify_status))
            result = subprocess.run(["bash", str(ROOT / "build.sh"), "verify-bundle"],
                                    env=env, capture_output=True, text=True)
            links = {name: (framework / name).is_symlink() for name in ("CTranscribe", "Resources", "Versions/Current")}
            preserved = (framework / "CTranscribe").exists() and (framework / "CTranscribe").read_text() == "flattened binary"
            return result, links, preserved, log.read_text() if log.exists() else ""

    def test_repaired_artifact_is_resigned_and_strictly_verified(self):
        result, links, _, log = self.bundle_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all(links.values()))
        self.assertEqual(len(log.splitlines()), 3)
        self.assertIn("--verify --deep --strict", log)

    def test_missing_app_fails_before_signing(self):
        result, _, _, log = self.bundle_check(missing_app=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Build the Release app", result.stderr)
        self.assertEqual(log, "")

    def test_incomplete_framework_preserves_existing_files_and_does_not_sign(self):
        result, links, preserved, log = self.bundle_check(incomplete=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("incomplete", result.stderr)
        self.assertFalse(any(links.values()))
        self.assertTrue(preserved)
        self.assertEqual(log, "")

    def test_failed_strict_verification_is_not_success(self):
        result, _, _, _ = self.bundle_check(verify_status=47)
        self.assertEqual(result.returncode, 47)


if __name__ == "__main__":
    unittest.main()
