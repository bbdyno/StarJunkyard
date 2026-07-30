#!/usr/bin/env python3
"""Guard isolated issue worktrees and run the shared StarJunkyard quality gate."""

from __future__ import annotations

import argparse
import fnmatch
import json
import shlex
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Sequence


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DEFINITIONS = ROOT / "agent-harness" / "tasks.json"


class HarnessError(ValueError):
    """A task definition, worktree, or validation violates the harness contract."""


@dataclass(frozen=True)
class Task:
    identifier: str
    issue: int
    title: str
    branch: str
    base_ref: str
    worktree_hint: str
    owned_paths: tuple[str, ...]
    validation_profile: str


@dataclass(frozen=True)
class StepResult:
    name: str
    state: str
    duration: float
    command: tuple[str, ...]


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise HarnessError(message)


def _git(repo: Path, *arguments: str, check: bool = True) -> str:
    result = subprocess.run(
        ["git", *arguments],
        cwd=repo,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise HarnessError(f"git {' '.join(arguments)} failed: {detail}")
    return result.stdout.rstrip("\n")


def _safe_relative_path(value: str, label: str) -> None:
    path = PurePosixPath(value)
    _require(value != "", f"{label} cannot be empty")
    _require(not path.is_absolute(), f"{label} must be relative: {value}")
    _require(".." not in path.parts, f"{label} cannot escape the repository: {value}")
    _require("\\" not in value, f"{label} must use POSIX separators: {value}")


def load_definitions(path: Path = DEFAULT_DEFINITIONS) -> tuple[dict[str, Any], dict[str, Task]]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise HarnessError(f"cannot load task definitions {path}: {error}") from error

    _require(isinstance(payload, dict), "task definitions must be a JSON object")
    _require(payload.get("schemaVersion") == 1, "unsupported task definition schema")
    policy = payload.get("branchPolicy")
    profiles = payload.get("validationProfiles")
    raw_tasks = payload.get("tasks")
    _require(isinstance(policy, dict), "branchPolicy must be an object")
    _require(isinstance(profiles, dict) and profiles, "validationProfiles must not be empty")
    _require(isinstance(raw_tasks, list) and raw_tasks, "tasks must not be empty")

    required_prefix = policy.get("requiredPrefix", "")
    forbidden = policy.get("forbiddenFragments", [])
    _require(isinstance(required_prefix, str), "requiredPrefix must be a string")
    _require(isinstance(forbidden, list) and all(isinstance(item, str) for item in forbidden),
             "forbiddenFragments must be strings")

    for profile_name, steps in profiles.items():
        _require(isinstance(profile_name, str) and profile_name, "profile name cannot be empty")
        _require(isinstance(steps, list) and steps, f"profile {profile_name} must contain steps")
        for step in steps:
            _require(isinstance(step, dict), f"profile {profile_name} steps must be objects")
            command = step.get("command")
            _require(isinstance(step.get("name"), str) and step["name"],
                     f"profile {profile_name} has a step without a name")
            _require(isinstance(command, list) and command and all(isinstance(part, str) for part in command),
                     f"profile {profile_name}/{step.get('name')} command must be a string array")

    tasks: dict[str, Task] = {}
    issues: set[int] = set()
    branches: set[str] = set()
    for raw in raw_tasks:
        _require(isinstance(raw, dict), "each task must be an object")
        identifier = raw.get("id")
        issue = raw.get("issue")
        branch = raw.get("branch")
        base_ref = raw.get("baseRef")
        owned_paths = raw.get("ownedPaths")
        profile = raw.get("validationProfile")
        _require(isinstance(identifier, str) and identifier, "task id cannot be empty")
        _require(identifier not in tasks, f"duplicate task id: {identifier}")
        _require(isinstance(issue, int) and issue > 0, f"{identifier}: issue must be positive")
        _require(issue not in issues, f"duplicate issue: {issue}")
        _require(isinstance(branch, str) and branch, f"{identifier}: branch cannot be empty")
        _require(branch not in branches, f"duplicate branch: {branch}")
        _require(branch.startswith(required_prefix),
                 f"{identifier}: branch must start with {required_prefix!r}")
        for fragment in forbidden:
            _require(fragment.casefold() not in branch.casefold(),
                     f"{identifier}: branch contains forbidden fragment {fragment!r}")
        _require(isinstance(base_ref, str) and base_ref, f"{identifier}: baseRef cannot be empty")
        _require(isinstance(owned_paths, list) and owned_paths and
                 all(isinstance(item, str) for item in owned_paths),
                 f"{identifier}: ownedPaths must contain strings")
        for pattern in owned_paths:
            _safe_relative_path(pattern, f"{identifier} owned path")
        _require(profile in profiles, f"{identifier}: unknown validation profile {profile!r}")
        hint = raw.get("worktreeHint", "")
        _require(isinstance(hint, str), f"{identifier}: worktreeHint must be a string")
        task = Task(
            identifier=identifier,
            issue=issue,
            title=str(raw.get("title", "")),
            branch=branch,
            base_ref=base_ref,
            worktree_hint=hint,
            owned_paths=tuple(owned_paths),
            validation_profile=profile,
        )
        tasks[identifier] = task
        issues.add(issue)
        branches.add(branch)
    return payload, tasks


def path_is_owned(path: str, patterns: Sequence[str]) -> bool:
    normalized = PurePosixPath(path).as_posix()
    return any(
        fnmatch.fnmatchcase(normalized, pattern)
        or PurePosixPath(normalized).match(pattern)
        for pattern in patterns
    )


def current_branch(repo: Path) -> str:
    branch = _git(repo, "branch", "--show-current")
    _require(branch != "", "detached HEAD is not allowed in an agent worktree")
    return branch


def dirty_paths(repo: Path) -> list[str]:
    output = _git(repo, "status", "--porcelain=v1", "-z")
    if not output:
        return []
    paths: list[str] = []
    records = output.split("\0")
    index = 0
    while index < len(records):
        record = records[index]
        index += 1
        if not record:
            continue
        _require(len(record) >= 4, f"cannot parse git status record: {record!r}")
        status = record[:2]
        path = record[3:]
        if "R" in status or "C" in status:
            if index < len(records) and records[index]:
                path = records[index]
                index += 1
        paths.append(PurePosixPath(path).as_posix())
    return sorted(set(paths))


def changed_paths(repo: Path, base_ref: str) -> list[str]:
    _git(repo, "rev-parse", "--verify", f"{base_ref}^{{commit}}")
    committed = _git(repo, "diff", "--name-only", "--diff-filter=ACMRTUXB", f"{base_ref}...HEAD")
    working = _git(repo, "diff", "--name-only", "--diff-filter=ACMRTUXB", "HEAD")
    untracked = _git(repo, "ls-files", "--others", "--exclude-standard")
    values = [line for group in (committed, working, untracked) for line in group.splitlines() if line]
    return sorted({PurePosixPath(value).as_posix() for value in values})


def guard_task(
    repo: Path,
    task: Task,
    forbidden_fragments: Sequence[str],
    require_clean: bool = False,
) -> tuple[list[str], list[str]]:
    branch = current_branch(repo)
    _require(branch == task.branch,
             f"{task.identifier}: expected branch {task.branch!r}, found {branch!r}")
    for fragment in forbidden_fragments:
        _require(fragment.casefold() not in branch.casefold(),
                 f"current branch contains forbidden fragment {fragment!r}")

    dirty = dirty_paths(repo)
    if require_clean:
        _require(not dirty, f"{task.identifier}: handoff requires a clean worktree ({len(dirty)} dirty paths)")
    changed = changed_paths(repo, task.base_ref)
    violations = [path for path in changed if not path_is_owned(path, task.owned_paths)]
    _require(not violations,
             f"{task.identifier}: paths outside ownership: {', '.join(violations)}")
    return changed, dirty


def _worktrees(repo: Path) -> dict[str, Path]:
    output = _git(repo, "worktree", "list", "--porcelain")
    result: dict[str, Path] = {}
    path: Path | None = None
    for line in output.splitlines():
        if line.startswith("worktree "):
            path = Path(line.removeprefix("worktree "))
        elif line.startswith("branch refs/heads/") and path is not None:
            result[line.removeprefix("branch refs/heads/")] = path
    return result


def status_rows(repo: Path, tasks: dict[str, Task], forbidden: Sequence[str]) -> list[list[str]]:
    worktrees = _worktrees(repo)
    rows: list[list[str]] = []
    for task in tasks.values():
        location = worktrees.get(task.branch)
        branch_policy = "OK" if not any(
            fragment.casefold() in task.branch.casefold() for fragment in forbidden
        ) else "FAIL"
        if location is None:
            rows.append([task.identifier, f"#{task.issue}", task.branch, "not checked out", "-",
                         f"{branch_policy}/-"])
            continue
        dirty = dirty_paths(location)
        try:
            changed = changed_paths(location, task.base_ref)
            violations = [path for path in changed if not path_is_owned(path, task.owned_paths)]
            scope = "OK" if not violations else f"FAIL({len(violations)})"
        except HarnessError:
            scope = "FAIL(base)"
        rows.append([
            task.identifier,
            f"#{task.issue}",
            task.branch,
            location.name,
            "clean" if not dirty else f"dirty({len(dirty)})",
            f"{branch_policy}/{scope}",
        ])
    return rows


def print_table(headers: Sequence[str], rows: Sequence[Sequence[str]]) -> None:
    widths = [len(header) for header in headers]
    for row in rows:
        for index, value in enumerate(row):
            widths[index] = max(widths[index], len(value))
    print("  ".join(header.ljust(widths[index]) for index, header in enumerate(headers)))
    print("  ".join("-" * width for width in widths))
    for row in rows:
        print("  ".join(value.ljust(widths[index]) for index, value in enumerate(row)))


def _simulator_id(repo: Path) -> str:
    devices = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        cwd=repo,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if devices.returncode != 0:
        raise HarnessError(f"cannot list iOS simulators: {devices.stderr.decode().strip()}")
    selector = subprocess.run(
        ["python3", "tools/select_ios_simulator.py"],
        cwd=repo,
        check=False,
        input=devices.stdout,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if selector.returncode != 0:
        raise HarnessError(f"cannot select iOS simulator: {selector.stderr.decode().strip()}")
    identifier = selector.stdout.decode().strip()
    _require(identifier != "", "simulator selector returned an empty identifier")
    return identifier


def run_profile(
    repo: Path,
    profile: Sequence[dict[str, Any]],
    *,
    dry_run: bool = False,
    keep_going: bool = False,
) -> list[StepResult]:
    results: list[StepResult] = []
    simulator_id: str | None = "<simulator-id>" if dry_run else None
    substitutions = {"derived_data_path": str(repo / "Derived" / "AgentHarness")}
    failed = False
    for step in profile:
        raw_command = tuple(step["command"])
        needs_simulator = any("{simulator_id}" in part for part in raw_command)
        if failed and not keep_going:
            results.append(StepResult(step["name"], "SKIP", 0, raw_command))
            continue
        if needs_simulator and simulator_id is None:
            simulator_id = _simulator_id(repo)
        values = {**substitutions, "simulator_id": simulator_id or ""}
        command = tuple(part.format(**values) for part in raw_command)
        print(f"\n[{len(results) + 1}/{len(profile)}] {step['name']}", flush=True)
        print("$ " + shlex.join(command), flush=True)
        start = time.monotonic()
        return_code = 0
        if not dry_run:
            return_code = subprocess.run(command, cwd=repo, check=False).returncode
        duration = time.monotonic() - start
        state = "DRY" if dry_run else ("PASS" if return_code == 0 else "FAIL")
        results.append(StepResult(step["name"], state, duration, command))
        failed |= return_code != 0
    return results


def print_verification_summary(results: Sequence[StepResult]) -> None:
    print("\nValidation summary")
    print_table(
        ("STATE", "SECONDS", "STEP"),
        [[result.state, f"{result.duration:.1f}", result.name] for result in results],
    )
    failed = sum(result.state == "FAIL" for result in results)
    print(f"\nResult: {'FAIL' if failed else 'PASS'} ({len(results) - failed}/{len(results)} steps non-failing)")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=ROOT, help="worktree to inspect")
    parser.add_argument("--definitions", type=Path, default=DEFAULT_DEFINITIONS,
                        help="task definition JSON")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("validate-definitions", help="validate task definitions only")
    subparsers.add_parser("status", help="show all registered worktrees and guard state")
    guard = subparsers.add_parser("guard", help="check branch, dirty state, and path ownership")
    guard.add_argument("task")
    guard.add_argument("--require-clean", action="store_true", help="fail when the worktree is dirty")
    verify = subparsers.add_parser("verify", help="guard a task and run its shared quality gate")
    verify.add_argument("task")
    verify.add_argument("--require-clean", action="store_true", help="require a committed handoff")
    verify.add_argument("--dry-run", action="store_true", help="print commands without executing them")
    verify.add_argument("--keep-going", action="store_true", help="continue after a failed step")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    repo = args.repo.resolve()
    try:
        payload, tasks = load_definitions(args.definitions.resolve())
        forbidden = payload["branchPolicy"].get("forbiddenFragments", [])
        if args.command == "validate-definitions":
            print(f"definitions passed: {len(tasks)} tasks, "
                  f"{len(payload['validationProfiles'])} validation profiles")
            return 0
        if args.command == "status":
            print(f"{payload.get('repository', 'repository')} agent status")
            print_table(
                ("TASK", "ISSUE", "BRANCH", "WORKTREE", "DIRTY", "POLICY/SCOPE"),
                status_rows(repo, tasks, forbidden),
            )
            return 0

        task = tasks.get(args.task)
        _require(task is not None, f"unknown task {args.task!r}; choose: {', '.join(tasks)}")
        changed, dirty = guard_task(repo, task, forbidden, args.require_clean)
        print(f"guard passed: {task.identifier}, branch={task.branch}, "
              f"changed={len(changed)}, dirty={len(dirty)}, scope=owned", flush=True)
        if args.command == "guard":
            return 0

        profile = payload["validationProfiles"][task.validation_profile]
        results = run_profile(repo, profile, dry_run=args.dry_run, keep_going=args.keep_going)
        print_verification_summary(results)
        return 1 if any(result.state == "FAIL" for result in results) else 0
    except (HarnessError, KeyError, OSError, subprocess.SubprocessError) as error:
        print(f"harness failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
