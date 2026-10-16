#!/usr/bin/env python3
"""Run local release checks and preserve evidence; live checks remain explicit."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
MANUAL_CHECKS = (
    "microphone_and_device_recovery", "long_talk_and_pause_resume", "offline_translation",
    "ime_delivery", "accessibility_and_layout", "signed_update_and_rollback", "recorded_demo",
)


def fingerprint(root=ROOT):
    digest = hashlib.sha256()
    for folder in ("Sources", "Tests", "scripts", "connectingCaptions.xcodeproj", ".github/workflows"):
        for path in sorted((root / folder).rglob("*")):
            if not path.is_file() or any(part in {"__pycache__", "xcuserdata"} for part in path.parts):
                continue
            digest.update(str(path.relative_to(root)).encode() + b"\0")
            digest.update(hashlib.sha256(path.read_bytes()).digest())
    for name in ("Info.plist", "connectingCaptions.entitlements", "Package.swift", "Package.resolved",
                 "build.sh", ".swiftlint.yml", "xcconfig/Shared.xcconfig"):
        path = root / name
        digest.update(name.encode() + b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def manual_complete(evidence, source_fingerprint):
    return (isinstance(evidence, dict)
            and evidence.get("sourceFingerprint") == source_fingerprint
            and isinstance(evidence.get("reviewer"), str) and bool(evidence["reviewer"].strip())
            and isinstance(evidence.get("checks"), dict)
            and all(isinstance(evidence["checks"].get(name), dict)
                    and evidence["checks"][name].get("status") == "passed"
                    and isinstance(evidence["checks"][name].get("notes"), str)
                    and bool(evidence["checks"][name]["notes"].strip()) for name in MANUAL_CHECKS))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "release-evidence")
    parser.add_argument("--quality", type=Path, help="Human-reviewed JSONL from a real recorded talk")
    parser.add_argument("--manual-evidence", type=Path)
    parser.add_argument("--ui", action="store_true", help="Also run the non-listening UI smoke test")
    parser.add_argument("--require-ready", action="store_true", help="Fail unless automatic, quality and manual checks all pass")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    source_fingerprint = fingerprint()
    manifest = {"sourceFingerprint": source_fingerprint, "reviewer": "",
                "checks": {name: {"status": "pending", "notes": ""} for name in MANUAL_CHECKS}}
    template = output / "manual-checks.template.json"
    template.write_text(json.dumps(manifest, indent=2) + "\n")
    env = dict(os.environ)
    if not env.get("DEVELOPER_DIR") and Path("/Applications/Xcode.app/Contents/Developer").exists():
        env["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
    commands = [
        ("test-wiring", ["sh", "scripts/test-omitted-tests.sh"]),
        ("team-id", ["bash", "scripts/check-team-id.sh"]),
        ("ui-copy", ["sh", "scripts/test-ui-copy.sh"]),
        ("docs", ["sh", "scripts/test-docs-copy.sh"]),
        ("quality-vectors", ["sh", "scripts/test-quality-score.sh"]),
        ("interface-catalog", [sys.executable, "scripts/update-interface-catalog.py", "--check"]),
        ("python", [sys.executable, "-m", "unittest", "discover", "-s", "scripts", "-p", "test_*.py"]),
        ("paste-keys", ["sh", "Tests/run_paste_key_cache_tests.sh"]),
        ("history", ["sh", "Tests/run_history_persistence_tests.sh"]),
        ("lint", ["swiftlint", "lint", "--strict", "--no-cache", "--quiet"]),
    ]
    xcode = ["xcodebuild", "test", "-project", "connectingCaptions.xcodeproj", "-scheme", "connectingCaptions",
             "-destination", "platform=macOS,arch=arm64", "-derivedDataPath", str(ROOT / "DerivedData"),
             "-skip-testing:ConnectingCaptionsIntegrationTests/DictationE2ETests/testDictationEndToEnd_whisperTiny_transcribesFixture",
             "-test-timeouts-enabled", "YES", "-maximum-test-execution-time-allowance", "300",
             "-resultBundlePath", str(output / (datetime.now(timezone.utc).strftime("Tests-%Y%m%dT%H%M%S%fZ") + ".xcresult")),
             "CODE_SIGN_IDENTITY=-"]
    if not args.ui:
        xcode.append("-skip-testing:ConnectingCaptionsUITests")
    commands.append(("xcode-tests", xcode))
    commands.append(("release-build", [
        "xcodebuild", "build", "-project", "connectingCaptions.xcodeproj", "-scheme", "connectingCaptions",
        "-configuration", "Release", "-destination", "platform=macOS,arch=arm64",
        "-derivedDataPath", str(ROOT / "DerivedData"), "CODE_SIGN_IDENTITY=-",
    ]))
    commands.append(("release-bundle", ["bash", "build.sh", "verify-bundle"]))
    results = []
    for name, command in commands:
        print(f"Running {name}…", flush=True)
        log = output / f"{name}.log"
        try:
            with log.open("w") as stream:
                process = subprocess.run(command, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT,
                                         timeout=1200 if name in {"xcode-tests", "release-build"} else 180)
            status = "passed" if process.returncode == 0 else "failed"
        except (OSError, subprocess.TimeoutExpired) as error:
            with log.open("a") as stream:
                stream.write(f"\n{error}\n")
            status = "failed"
        results.append({"name": name, "status": status, "log": str(log)})
        print(f"{name}: {status}", flush=True)
    quality_passed = False
    if args.quality:
        with (output / "quality.log").open("w") as stream:
            quality_passed = subprocess.run([sys.executable, str(ROOT / "scripts/score-theater-talk.py"),
                                            str(args.quality.resolve()), "--gate", "--json-output", str(output / "quality.json")],
                                           stdout=stream, stderr=subprocess.STDOUT).returncode == 0
    manual_passed = False
    if args.manual_evidence:
        try:
            evidence = json.loads(args.manual_evidence.read_text())
            manual_passed = manual_complete(evidence, source_fingerprint)
        except (ValueError, OSError, AttributeError, TypeError):
            pass
    source_unchanged = fingerprint() == source_fingerprint
    automatic_passed = source_unchanged and all(row["status"] == "passed" for row in results)
    ready = automatic_passed and quality_passed and manual_passed
    report = {"recordedAt": datetime.now(timezone.utc).isoformat(), "sourceFingerprint": source_fingerprint,
              "sourceUnchanged": source_unchanged,
              "automaticPassed": automatic_passed, "qualityPassed": quality_passed, "manualPassed": manual_passed,
              "releaseReady": ready, "checks": results}
    (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Automatic checks: {automatic_passed}; real quality: {quality_passed}; manual checks: {manual_passed}")
    if not source_unchanged:
        print("Release inputs changed during validation; rerun against the finished changes.")
    print(f"Evidence: {output / 'summary.json'}")
    return 0 if automatic_passed and (ready or not args.require_ready) else 1


if __name__ == "__main__":
    raise SystemExit(main())
