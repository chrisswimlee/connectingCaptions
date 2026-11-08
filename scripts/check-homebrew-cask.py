#!/usr/bin/env python3
"""Keep the Homebrew cask pointed at the app folder inside that version's zip.

The published 1.6.16 zip contains "Connecting Captions.app".
A later zip contains "Connecting Captions Pro.app".
The cask's version, name, and app move together. This script fails when they do not.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

LEGACY_VERSION = "1.6.16"
LEGACY_APP = "Connecting Captions.app"
PRO_APP = "Connecting Captions Pro.app"
PRO_NAME = "Connecting Captions Pro"


def parse_cask(text: str) -> tuple[str, str, str]:
    version = _field(text, "version")
    name = _field(text, "name")
    app = _field(text, "app")
    return version, name, app


def _field(text: str, key: str) -> str:
    match = re.search(rf'^\s*{key}\s+"([^"]+)"', text, re.M)
    if match is None:
        raise ValueError(f"The cask has no {key} line.")
    return match.group(1)


def mismatch(version: str, name: str, app: str) -> str | None:
    if version == LEGACY_VERSION:
        if app != LEGACY_APP or name != "Connecting Captions":
            return (
                f"Cask {version} still installs the published zip, which contains {LEGACY_APP}. "
                f"It says name {name!r} and app {app!r}."
            )
        return None
    if app != PRO_APP or name != PRO_NAME:
        return (
            f"Cask {version} must install {PRO_APP} under the name {PRO_NAME}. "
            f"It says name {name!r} and app {app!r}."
        )
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cask", type=Path)
    parser.add_argument("--release-version", default="")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()

    cask = args.cask
    if cask is None or not cask.is_file():
        print("Homebrew cask is not in this checkout. Update it when you publish the zip.")
        print(f"version, sha256, name {PRO_NAME!r}, and app {PRO_APP!r} change in the same edit.")
        return 0

    version, name, app = parse_cask(cask.read_text(encoding="utf-8"))
    problem = mismatch(version, name, app)
    if problem:
        print(problem, file=sys.stderr)
        return 1
    if args.release_version and version != args.release_version:
        print(
            f"The cask is still {version} ({app}). "
            f"After {args.release_version} is notarized, set that version, its sha256, "
            f"name {PRO_NAME!r}, and app {PRO_APP!r} in the same edit."
        )
    else:
        print(f"Cask {version} installs {app}.")
    return 0


def self_test() -> int:
    assert mismatch(LEGACY_VERSION, "Connecting Captions", LEGACY_APP) is None
    assert mismatch(LEGACY_VERSION, PRO_NAME, PRO_APP) is not None
    assert mismatch("1.6.17", PRO_NAME, PRO_APP) is None
    assert mismatch("1.6.17", "Connecting Captions", LEGACY_APP) is not None
    legacy = 'cask "connectingcaptions" do\n  version "1.6.16"\n  name "Connecting Captions"\n  app "Connecting Captions.app"\nend\n'
    assert parse_cask(legacy) == (LEGACY_VERSION, "Connecting Captions", LEGACY_APP)
    print("cask check ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
