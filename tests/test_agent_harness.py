from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("agent_harness", ROOT / "tools" / "agent_harness.py")
assert SPEC and SPEC.loader
HARNESS = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = HARNESS
SPEC.loader.exec_module(HARNESS)


def run_git(repo: Path, *arguments: str) -> None:
    subprocess.run(["git", *arguments], cwd=repo, check=True, stdout=subprocess.PIPE)


def definitions(*, branch: str = "issue/42-example", owned_paths: list[str] | None = None) -> dict:
    return {
        "schemaVersion": 1,
        "repository": "test",
        "branchPolicy": {
            "requiredPrefix": "issue/",
            "forbiddenFragments": ["codex"],
        },
        "validationProfiles": {
            "test": [
                {"name": "No operation", "command": ["python3", "-c", "pass"]},
            ]
        },
        "tasks": [
            {
                "id": "issue-42",
                "issue": 42,
                "title": "Example",
                "branch": branch,
                "baseRef": "main",
                "worktreeHint": "../worktrees/issue-42",
                "ownedPaths": owned_paths or ["Sources/**"],
                "validationProfile": "test",
            }
        ],
    }


class AgentHarnessDefinitionTests(unittest.TestCase):
    def write_definitions(self, directory: Path, payload: dict) -> Path:
        path = directory / "tasks.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def test_repository_definitions_are_valid_and_have_no_codex_branches(self) -> None:
        payload, tasks = HARNESS.load_definitions(ROOT / "agent-harness" / "tasks.json")

        self.assertEqual(4, len(tasks))
        self.assertEqual({21, 22, 25, 27}, {task.issue for task in tasks.values()})
        for task in tasks.values():
            self.assertTrue(task.branch.startswith("issue/"))
            self.assertNotIn("codex", task.branch.casefold())
        self.assertIn("full-ios", payload["validationProfiles"])
        commands = [
            step["command"] for step in payload["validationProfiles"]["full-ios"]
        ]
        self.assertIn(["tuist", "generate", "--no-open"], commands)
        self.assertTrue(any(command[0] == "xcodebuild" and "test" in command for command in commands))
        self.assertTrue(any(command[-1] == "--release" for command in commands))

    def test_rejects_forbidden_branch_fragment_case_insensitively(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = self.write_definitions(Path(temporary), definitions(branch="issue/42-CoDeX-work"))
            with self.assertRaisesRegex(HARNESS.HarnessError, "forbidden fragment"):
                HARNESS.load_definitions(path)

    def test_rejects_ownership_path_that_escapes_repository(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = self.write_definitions(Path(temporary), definitions(owned_paths=["../Shared/**"]))
            with self.assertRaisesRegex(HARNESS.HarnessError, "cannot escape"):
                HARNESS.load_definitions(path)

    def test_path_ownership_uses_explicit_posix_globs(self) -> None:
        patterns = ("Sources/**", "README.md")

        self.assertTrue(HARNESS.path_is_owned("Sources/Feature/Model.swift", patterns))
        self.assertTrue(HARNESS.path_is_owned("README.md", patterns))
        self.assertFalse(HARNESS.path_is_owned("Tests/FeatureTests.swift", patterns))


class AgentHarnessGitGuardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.repo = Path(self.temporary.name)
        run_git(self.repo, "init", "-b", "main")
        run_git(self.repo, "config", "user.email", "harness@example.invalid")
        run_git(self.repo, "config", "user.name", "Harness Test")
        (self.repo / "Sources").mkdir()
        (self.repo / "Sources" / "Base.swift").write_text("let base = true\n", encoding="utf-8")
        run_git(self.repo, "add", ".")
        run_git(self.repo, "commit", "-m", "base")
        run_git(self.repo, "switch", "-c", "issue/42-example")
        self.task = HARNESS.Task(
            identifier="issue-42",
            issue=42,
            title="Example",
            branch="issue/42-example",
            base_ref="main",
            worktree_hint="",
            owned_paths=("Sources/**",),
            validation_profile="test",
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_guard_accepts_owned_dirty_work_but_handoff_requires_clean(self) -> None:
        (self.repo / "Sources" / "Feature.swift").write_text("let feature = true\n", encoding="utf-8")

        changed, dirty = HARNESS.guard_task(self.repo, self.task, ("codex",))
        self.assertEqual(["Sources/Feature.swift"], changed)
        self.assertEqual(["Sources/Feature.swift"], dirty)
        with self.assertRaisesRegex(HARNESS.HarnessError, "clean worktree"):
            HARNESS.guard_task(self.repo, self.task, ("codex",), require_clean=True)

    def test_guard_rejects_file_outside_owned_paths(self) -> None:
        (self.repo / "README.md").write_text("unexpected\n", encoding="utf-8")

        with self.assertRaisesRegex(HARNESS.HarnessError, "outside ownership.*README.md"):
            HARNESS.guard_task(self.repo, self.task, ("codex",))

    def test_dirty_parser_preserves_leading_space_for_tracked_change(self) -> None:
        (self.repo / "Sources" / "Base.swift").write_text("let base = false\n", encoding="utf-8")

        self.assertEqual(["Sources/Base.swift"], HARNESS.dirty_paths(self.repo))

    def test_guard_checks_exact_task_branch(self) -> None:
        run_git(self.repo, "switch", "main")

        with self.assertRaisesRegex(HARNESS.HarnessError, "expected branch"):
            HARNESS.guard_task(self.repo, self.task, ("codex",))

    def test_committed_owned_change_is_compared_with_base(self) -> None:
        (self.repo / "Sources" / "Feature.swift").write_text("let feature = true\n", encoding="utf-8")
        run_git(self.repo, "add", ".")
        run_git(self.repo, "commit", "-m", "feature")

        changed, dirty = HARNESS.guard_task(
            self.repo, self.task, ("codex",), require_clean=True
        )
        self.assertEqual(["Sources/Feature.swift"], changed)
        self.assertEqual([], dirty)


class AgentHarnessVerificationTests(unittest.TestCase):
    def test_dry_run_expands_validation_placeholders_without_tools(self) -> None:
        profile = [
            {"name": "Generate", "command": ["tuist", "generate", "--no-open"]},
            {
                "name": "Test",
                "command": [
                    "xcodebuild",
                    "-destination",
                    "platform=iOS Simulator,id={simulator_id}",
                    "-derivedDataPath",
                    "{derived_data_path}",
                    "test",
                ],
            },
        ]

        results = HARNESS.run_profile(ROOT, profile, dry_run=True)

        self.assertEqual(["DRY", "DRY"], [result.state for result in results])
        self.assertIn("platform=iOS Simulator,id=<simulator-id>", results[1].command)
        self.assertIn(str(ROOT / "Derived" / "AgentHarness"), results[1].command)


if __name__ == "__main__":
    unittest.main()
