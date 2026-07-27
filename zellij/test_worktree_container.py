#!/usr/bin/env python3
"""End-to-end tests for generic bare-repo worktree containers."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
GCLONE = HERE / "clone-worktree-container.sh"
NWT = HERE / "new-worktree.sh"
RMWT = HERE / "remove-worktree.sh"


class WorktreeContainerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.source = self.root / "source"
        self.remote = self.root / "remote.git"
        self.container = self.root / "container"
        self.env = os.environ.copy()
        for name in (
            "PROXIMAL_MONO_ROOT",
            "PROXIMAL_BARE_REPO",
            "PROXIMAL_WORKTREES_DIR",
            "PROXIMAL_BRANCH_PREFIX",
            "ZELLIJ",
        ):
            self.env.pop(name, None)
        self.env.update(
            {
                "GIT_CONFIG_GLOBAL": "/dev/null",
                "PI_ZELLIJ_STATE_DIR": str(self.root / "pi-state"),
                # If nearest-container discovery regresses, fail hermetically
                # instead of falling back to the user's real mono repository.
                "WORKTREE_CONTAINER_DEFAULT_ROOT": str(self.root / "no-fallback"),
            }
        )

        self.git("init", "--initial-branch=main", str(self.source))
        (self.source / "README.md").write_text("test repository\n", encoding="utf-8")
        self.git("-C", str(self.source), "add", "README.md")
        commit_env = self.env | {
            "GIT_AUTHOR_NAME": "Test User",
            "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test User",
            "GIT_COMMITTER_EMAIL": "test@example.com",
        }
        subprocess.run(
            ["git", "-C", str(self.source), "commit", "-m", "initial"],
            check=True,
            capture_output=True,
            text=True,
            env=commit_env,
        )
        self.git("clone", "--bare", str(self.source), str(self.remote))

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def git(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", *args],
            check=True,
            capture_output=True,
            text=True,
            env=self.env,
        )

    def run_script(
        self, script: Path, *args: str, cwd: Path | None = None
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(script), *args],
            cwd=cwd,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_gclone_then_nwt_and_rmwt_use_discovered_container(self) -> None:
        result = self.run_script(GCLONE, str(self.remote), str(self.container))
        self.assertEqual(result.returncode, 0, result.stderr)

        bare = self.container / ".bare"
        main = self.container / "worktrees" / "main"
        self.assertTrue(bare.is_dir())
        self.assertTrue(main.is_dir())
        self.assertTrue((self.container / "main").is_symlink())
        self.assertEqual(os.readlink(self.container / "main"), "worktrees/main")
        self.assertEqual(
            self.git("--git-dir", str(bare), "symbolic-ref", "--short", "HEAD").stdout.strip(),
            "main",
        )
        self.assertEqual(
            self.git(
                "--git-dir",
                str(bare),
                "symbolic-ref",
                "--short",
                "refs/remotes/origin/HEAD",
            ).stdout.strip(),
            "origin/main",
        )
        self.assertEqual(
            self.git(
                "--git-dir", str(bare), "config", "--get", "remote.origin.fetch"
            ).stdout.strip(),
            "+refs/heads/*:refs/remotes/origin/*",
        )

        create = self.run_script(NWT, "discovery-test", cwd=main)
        self.assertEqual(create.returncode, 0, create.stderr)
        feature = self.container / "worktrees" / "discovery-test"
        self.assertTrue(feature.is_dir())
        self.assertEqual(
            self.git("-C", str(feature), "branch", "--show-current").stdout.strip(),
            "tarush/discovery-test",
        )

        remove = self.run_script(RMWT, "discovery-test", cwd=self.container)
        self.assertEqual(remove.returncode, 0, remove.stderr)
        self.assertFalse(feature.exists())
        missing_branch = subprocess.run(
            [
                "git",
                "--git-dir",
                str(bare),
                "show-ref",
                "--verify",
                "--quiet",
                "refs/heads/tarush/discovery-test",
            ],
            env=self.env,
            check=False,
        )
        self.assertNotEqual(missing_branch.returncode, 0)

    def test_non_main_default_and_missing_remote_head_remain_protected(self) -> None:
        main_oid = self.git(
            "--git-dir", str(self.remote), "rev-parse", "refs/heads/main"
        ).stdout.strip()
        self.git(
            "--git-dir",
            str(self.remote),
            "update-ref",
            "refs/heads/trunk",
            main_oid,
        )
        self.git("--git-dir", str(self.remote), "update-ref", "-d", "refs/heads/main")
        self.git(
            "--git-dir", str(self.remote), "symbolic-ref", "HEAD", "refs/heads/trunk"
        )

        result = self.run_script(GCLONE, str(self.remote), str(self.container))
        self.assertEqual(result.returncode, 0, result.stderr)

        bare = self.container / ".bare"
        trunk = self.container / "worktrees" / "trunk"
        self.assertTrue(trunk.is_dir())
        self.assertFalse((self.container / "main").exists())

        create = self.run_script(NWT, "trunk-test", cwd=trunk)
        self.assertEqual(create.returncode, 0, create.stderr)
        feature = self.container / "worktrees" / "trunk-test"
        self.assertEqual(
            self.git("-C", str(feature), "rev-parse", "HEAD").stdout.strip(), main_oid
        )
        remove_feature = self.run_script(RMWT, "trunk-test", cwd=self.container)
        self.assertEqual(remove_feature.returncode, 0, remove_feature.stderr)

        # Simulate a legacy bare clone without refs/remotes/origin/HEAD. The
        # bare repository's own HEAD must still protect its default worktree.
        self.git(
            "--git-dir",
            str(bare),
            "symbolic-ref",
            "--delete",
            "refs/remotes/origin/HEAD",
        )
        remove_default = self.run_script(RMWT, "--force", "trunk", cwd=self.container)
        self.assertNotEqual(remove_default.returncode, 0)
        self.assertIn("refusing to remove the default branch: trunk", remove_default.stderr)
        self.assertTrue(trunk.is_dir())
        self.git("--git-dir", str(bare), "show-ref", "--verify", "refs/heads/trunk")

    def test_failed_gclone_removes_partial_destination(self) -> None:
        missing_remote = self.root / "missing.git"

        result = self.run_script(GCLONE, str(missing_remote), str(self.container))

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Cleaning up incomplete worktree container", result.stderr)
        self.assertFalse(self.container.exists())


if __name__ == "__main__":
    unittest.main()
