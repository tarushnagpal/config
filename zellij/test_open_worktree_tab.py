#!/usr/bin/env python3
"""Focused tests for stable-root worktree tab creation."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "open-worktree-tab.sh"
WORKTREE_LAYOUT = HERE / "layouts" / "worktree.kdl"


class OpenWorktreeTabTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.mono = self.root / "mono"
        self.worktree = self.root / "worktree"
        self.bin = self.root / "bin"
        self.capture = self.root / "capture"
        self.mono.mkdir()
        self.worktree.mkdir()
        self.bin.mkdir()
        fake = self.bin / "zellij"
        fake.write_text(
            """#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import sys

args = sys.argv[1:]
capture = Path(os.environ["CAPTURE"])
if args[:2] == ["action", "list-tabs"]:
    print("[]")
    raise SystemExit(0)
if args[:2] == ["action", "new-tab"]:
    capture.with_suffix(".json").write_text(json.dumps(args))
    layout = Path(args[args.index("--layout") + 1])
    capture.with_suffix(".path").write_text(str(layout))
    shutil.copyfile(layout, capture.with_suffix(".kdl"))
    print("17")
    raise SystemExit(0)
raise SystemExit(2)
""",
            encoding="utf-8",
        )
        fake.chmod(0o755)

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def run_script(
        self, layout: Path, *, explicit_root: bool = True
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env.pop("PROXIMAL_MONO_ROOT", None)
        env.update(
            {
                "PATH": f"{self.bin}:{env['PATH']}",
                "CAPTURE": str(self.capture),
                "ZELLIJ": "1",
            }
        )
        if explicit_root:
            env["PROXIMAL_MONO_ROOT"] = str(self.mono)
        return subprocess.run(
            [str(SCRIPT), "feature", str(self.worktree), str(layout)],
            text=True,
            capture_output=True,
            env=env,
            check=False,
        )

    def test_new_tab_is_mono_rooted_while_command_panes_are_worktree_rooted(self) -> None:
        source = self.root / "source.kdl"
        source_text = """layout {
    pane name="blocked" command="zsh" {
        args "-ic" "echo hi"
    }
    pane name="leaf" command = "zsh"
    pane name="explicit" command="tool" cwd = "/already" {
    }
    pane {
        plugin location="zellij:status-bar"
    }
}
"""
        source.write_text(source_text, encoding="utf-8")

        result = self.run_script(source)

        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(self.capture.with_suffix(".json").read_text())
        self.assertEqual(args[args.index("--cwd") + 1], str(self.mono.resolve()))
        rendered_path = Path(self.capture.with_suffix(".path").read_text())
        self.assertFalse(rendered_path.exists(), "temporary rendered layout was not removed")
        rendered = self.capture.with_suffix(".kdl").read_text()
        worktree_json = json.dumps(str(self.worktree.resolve()))
        self.assertIn(f'pane name="blocked" command="zsh" cwd={worktree_json} {{', rendered)
        self.assertIn(f'pane name="leaf" command = "zsh" cwd={worktree_json}', rendered)
        self.assertIn('pane name="explicit" command="tool" cwd = "/already" {', rendered)
        self.assertEqual(source.read_text(encoding="utf-8"), source_text)

    def test_container_root_is_discovered_from_worktree_path(self) -> None:
        container = self.root / "container"
        (container / ".bare").mkdir(parents=True)
        discovered_worktree = container / "worktrees" / "feature"
        discovered_worktree.mkdir(parents=True)
        self.worktree = discovered_worktree
        source = self.root / "discovery.kdl"
        source.write_text('layout {\n    pane command="zsh"\n}\n', encoding="utf-8")

        result = self.run_script(source, explicit_root=False)

        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(self.capture.with_suffix(".json").read_text())
        self.assertEqual(args[args.index("--cwd") + 1], str(container.resolve()))

    def test_non_ascii_worktree_path_uses_kdl_compatible_literal_unicode(self) -> None:
        unicode_worktree = self.root / "wörk-tree"
        unicode_worktree.mkdir()
        self.worktree = unicode_worktree
        source = self.root / "unicode.kdl"
        source.write_text('layout {\n    pane command="zsh"\n}\n', encoding="utf-8")

        result = self.run_script(source)

        self.assertEqual(result.returncode, 0, result.stderr)
        rendered = self.capture.with_suffix(".kdl").read_text(encoding="utf-8")
        self.assertIn(f'cwd={json.dumps(str(unicode_worktree.resolve()), ensure_ascii=False)}', rendered)
        self.assertNotIn(r"\u00f6", rendered)

    def test_repository_layout_roots_all_four_command_panes_in_worktree(self) -> None:
        result = self.run_script(WORKTREE_LAYOUT)

        self.assertEqual(result.returncode, 0, result.stderr)
        rendered = self.capture.with_suffix(".kdl").read_text()
        worktree_json = json.dumps(str(self.worktree.resolve()))
        command_lines = [line for line in rendered.splitlines() if "command=" in line]
        self.assertEqual(len(command_lines), 4)
        self.assertTrue(all(f"cwd={worktree_json}" in line for line in command_lines), command_lines)


if __name__ == "__main__":
    unittest.main()
