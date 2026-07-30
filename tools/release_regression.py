#!/usr/bin/env python3
"""Run the complete unsigned iOS App Store readiness regression."""

from __future__ import annotations

import argparse
import json
import shlex
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence


ROOT = Path(__file__).resolve().parents[1]
PREFERRED_IPHONES = (
    "iPhone 17 Pro",
    "iPhone 17",
    "iPhone 16 Pro",
    "iPhone 16",
    "iPhone 15 Pro",
    "iPhone 15",
)
PREFERRED_IPADS = (
    "iPad Pro 13-inch (M5)",
    "iPad Pro 13-inch (M4)",
    "iPad Air 13-inch (M3)",
    "iPad Air 13-inch (M2)",
    "iPad Pro (12.9-inch) (6th generation)",
    "iPad Pro (11-inch) (4th generation)",
)


@dataclass(frozen=True)
class Step:
    name: str
    command: tuple[str, ...]


def select_device(payload: dict[str, Any], family: str) -> str:
    preferred = PREFERRED_IPHONES if family == "iPhone" else PREFERRED_IPADS
    candidates: list[tuple[int, str, str, str]] = []
    for runtime, devices in payload.get("devices", {}).items():
        for device in devices:
            name = str(device.get("name", ""))
            identifier = str(device.get("udid", ""))
            available = device.get("isAvailable", device.get("availability") == "(available)")
            if not available or not identifier or not name.startswith(family):
                continue
            try:
                preference = preferred.index(name)
            except ValueError:
                preference = len(preferred)
            candidates.append((preference, name, runtime, identifier))
    if not candidates:
        raise ValueError(f"no available {family} simulator was reported by simctl")
    candidates.sort()
    return candidates[0][3]


def discover_simulators() -> tuple[str, str]:
    result = subprocess.run(
        ("xcrun", "simctl", "list", "devices", "available", "--json"),
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    payload = json.loads(result.stdout)
    return select_device(payload, "iPhone"), select_device(payload, "iPad")


def build_steps(derived_data_path: Path, iphone_id: str, ipad_id: str, skip_ios: bool) -> list[Step]:
    steps = [
        Step("Python contract tests", ("python3", "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py")),
        Step("Release content and pixel assets", ("python3", "tools/validate_project.py", "--release")),
        Step("App Store release contracts", ("python3", "tools/validate_app_store_release.py")),
    ]
    if skip_ios:
        return steps

    common = (
        "-project", "StarJunkyard.xcodeproj",
        "-scheme", "StarJunkyard",
        "-quiet",
        "-derivedDataPath", str(derived_data_path),
        "CODE_SIGNING_ALLOWED=NO",
    )
    steps.extend(
        [
            Step("Generate Xcode project", ("tuist", "generate", "--no-open")),
            Step(
                "Unsigned generic iOS Release build",
                ("xcodebuild", *common, "-configuration", "Release", "-destination", "generic/platform=iOS", "build"),
            ),
            Step(
                "iPhone XCTest",
                ("xcodebuild", *common, "-configuration", "Debug", "-destination",
                 f"platform=iOS Simulator,id={iphone_id}", "test"),
            ),
            Step(
                "iPad XCTest",
                ("xcodebuild", *common, "-configuration", "Debug", "-destination",
                 f"platform=iOS Simulator,id={ipad_id}", "test"),
            ),
        ]
    )
    return steps


def run_step(step: Step, dry_run: bool) -> tuple[bool, float]:
    print(f"\n[{step.name}]\n$ {shlex.join(step.command)}", flush=True)
    if dry_run:
        return True, 0.0
    started = time.monotonic()
    try:
        return_code = subprocess.run(step.command, cwd=ROOT, check=False).returncode
    except FileNotFoundError as error:
        print(f"missing command: {error.filename}", file=sys.stderr)
        return False, time.monotonic() - started
    return return_code == 0, time.monotonic() - started


def parse_arguments(arguments: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="print the complete plan without executing commands")
    parser.add_argument("--skip-ios", action="store_true", help="run repository contracts only; intended for non-macOS CI")
    parser.add_argument("--keep-going", action="store_true", help="continue after a failed gate")
    parser.add_argument(
        "--derived-data-path",
        type=Path,
        default=ROOT / "Derived" / "ReleaseReadiness",
        help="Xcode DerivedData location",
    )
    return parser.parse_args(arguments)


def main(arguments: Sequence[str] | None = None) -> int:
    options = parse_arguments(arguments)
    if options.dry_run or options.skip_ios:
        iphone_id, ipad_id = "<iphone-simulator-id>", "<ipad-simulator-id>"
    else:
        try:
            iphone_id, ipad_id = discover_simulators()
        except (FileNotFoundError, subprocess.CalledProcessError, json.JSONDecodeError, ValueError) as error:
            print(f"simulator discovery failed: {error}", file=sys.stderr)
            return 1
        print(f"Selected simulators: iPhone={iphone_id}, iPad={ipad_id}")

    steps = build_steps(options.derived_data_path.resolve(), iphone_id, ipad_id, options.skip_ios)
    results: list[tuple[str, bool, float]] = []
    for step in steps:
        passed, duration = run_step(step, options.dry_run)
        results.append((step.name, passed, duration))
        if not passed and not options.keep_going:
            break

    print("\nRelease regression summary")
    for name, passed, duration in results:
        state = "PLAN" if options.dry_run else "PASS" if passed else "FAIL"
        print(f"- {state:4} {name} ({duration:.1f}s)")
    succeeded = len(results) == len(steps) and all(passed for _, passed, _ in results)
    if succeeded and not options.dry_run:
        print("Repository release gates passed. External App Store Connect blockers still remain.")
    return 0 if succeeded else 1


if __name__ == "__main__":
    raise SystemExit(main())
