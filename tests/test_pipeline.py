#!/usr/bin/env python3
import fnmatch
import hashlib
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ROLES = (
    "planner",
    "debater",
    "implementer",
    "reviewer",
    "security-reviewer",
    "tester",
    "linter",
    "commit-msg",
)
ALL_AGENTS = ("pipeline",) + ROLES
PLUGIN_RELATIVE = "plugins/opencode-pipeline-permissions.js"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def frontmatter(path):
    return path.read_text().split("---", 2)[1]


class PipelineRegressionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="opencode-pipeline-test-")
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.xdg = self.root / "xdg"
        self.config = self.xdg / "opencode"
        self.home.mkdir()
        self.xdg.mkdir()
        self.environment = os.environ.copy()
        self.environment.update(
            {
                "HOME": str(self.home),
                "XDG_CONFIG_HOME": str(self.xdg),
                "OPENCODE_PIPELINE_REPO_URL": ROOT.as_uri(),
            }
        )

    def tearDown(self):
        self.temporary.cleanup()

    def run_install(self, profile, *, failure_after=None, check=True):
        environment = self.environment.copy()
        if failure_after is not None:
            environment["OPENCODE_PIPELINE_FAIL_AFTER_REPLACE"] = str(failure_after)
        return subprocess.run(
            ["bash", str(ROOT / "install.sh"), profile],
            cwd=ROOT,
            env=environment,
            text=True,
            capture_output=True,
            check=check,
        )

    def installed_paths(self):
        return [self.config / "agents" / f"{agent}.md" for agent in ALL_AGENTS] + [
            self.config / PLUGIN_RELATIVE,
            self.config / ".opencode-pipeline-manifest.json",
        ]

    def snapshot_installation(self):
        return {str(path.relative_to(self.config)): path.read_bytes() for path in self.installed_paths()}

    def assert_no_transaction_temps(self):
        if not self.config.exists():
            return
        temporary_names = (
            ".opencode-pipeline-new-",
            ".opencode-pipeline-old-",
            ".opencode-pipeline-manifest-new-",
            ".opencode-pipeline-manifest-old-",
        )
        self.assertEqual(
            [],
            [path for path in self.config.rglob("*") if path.name.startswith(temporary_names)],
        )

    def assert_profile(self, profile_name):
        profile = json.loads((ROOT / "models" / "profiles" / f"{profile_name}.json").read_text())
        manifest = json.loads((self.config / ".opencode-pipeline-manifest.json").read_text())
        self.assertEqual(3, manifest["version"])
        self.assertEqual(profile_name, manifest["profile"])
        self.assertEqual(10, len(manifest["files"]))
        for agent, settings in profile["agents"].items():
            content = frontmatter(self.config / "agents" / f"{agent}.md")
            self.assertIn(f"\nmodel: {settings['model']}\n", content)
            if "variant" in settings:
                self.assertIn(f"\nvariant: {settings['variant']}\n", content)
            else:
                self.assertNotIn("\nvariant:", content)
        for relative, expected in manifest["files"].items():
            path = self.config / relative
            self.assertTrue(path.is_file())
            self.assertFalse(path.is_symlink())
            self.assertEqual(expected, sha256(path))

    def apply_plugin(self, configs):
        script = """
const factory = (await import(process.argv[1])).default
const configs = JSON.parse(await new Promise((resolve) => {
  let data = ""
  process.stdin.setEncoding("utf8")
  process.stdin.on("data", (chunk) => data += chunk)
  process.stdin.on("end", () => resolve(data))
}))
const hooks = await factory()
for (const config of configs) hooks.config(config)
process.stdout.write(JSON.stringify(configs))
"""
        result = subprocess.run(
            ["node", "--input-type=module", "-e", script, (ROOT / "plugins" / "opencode-pipeline-permissions.js").as_uri()],
            input=json.dumps(configs),
            text=True,
            capture_output=True,
            check=True,
        )
        return json.loads(result.stdout)

    def test_plugin_orders_denials_after_existing_rules(self):
        config = {
            "permission": {
                "task": {
                    "unrelated-first": "ask",
                    "planner": "allow",
                    "*": "allow",
                    "unrelated-last": "deny",
                }
            }
        }
        result = self.apply_plugin([config])[0]
        task = result["permission"]["task"]
        self.assertEqual(["unrelated-first", "*", "unrelated-last"], list(task)[:3])
        self.assertEqual(list(ROLES), list(task)[-len(ROLES):])
        self.assertTrue(all(task[role] == "deny" for role in ROLES))
        effective = None
        for pattern, action in task.items():
            if fnmatch.fnmatchcase("planner", pattern):
                effective = action
        self.assertEqual("deny", effective)

    def test_plugin_normalizes_missing_and_scalar_permissions(self):
        results = self.apply_plugin(
            [
                {},
                {"permission": "ask"},
                {"permission": {}},
                {"permission": {"task": "allow"}},
            ]
        )
        self.assertNotIn("*", results[0]["permission"])
        self.assertEqual("ask", results[1]["permission"]["*"])
        self.assertNotIn("*", results[2]["permission"]["task"])
        self.assertEqual("allow", results[3]["permission"]["task"]["*"])
        for result in results:
            task = result["permission"]["task"]
            self.assertEqual(list(ROLES), list(task)[-len(ROLES):])

    def test_agent_task_boundaries(self):
        for role in ROLES:
            content = frontmatter(ROOT / "agents" / f"{role}.md")
            self.assertEqual(1, content.splitlines().count("  task: deny"), role)

        lines = frontmatter(ROOT / "agents" / "pipeline.md").splitlines()
        task_start = lines.index("  task:") + 1
        task_rules = []
        for line in lines[task_start:]:
            if not line.startswith("    "):
                break
            key, value = line.strip().split(": ", 1)
            task_rules.append((key.strip('"'), value))
        self.assertEqual([("*", "deny")] + [(role, "allow") for role in ROLES], task_rules)

    def test_fresh_free_profile_installation(self):
        self.run_install("free")
        self.assert_profile("free")

    def test_fresh_gpt_profile_installation(self):
        self.run_install("gpt")
        self.assert_profile("gpt")

    def test_fresh_qwen3_8_27b_profile_installation(self):
        self.run_install("qwen3-8-27b")
        self.assert_profile("qwen3-8-27b")
        profile = json.loads((ROOT / "models" / "profiles" / "qwen3-8-27b.json").read_text())
        self.assertEqual(
            {
                "pipeline": "medium",
                "planner": "high",
                "debater": "high",
                "implementer": "high",
                "reviewer": "high",
                "security-reviewer": "high",
                "tester": "medium",
                "linter": "low",
                "commit-msg": "low",
            },
            {agent: settings["variant"] for agent, settings in profile["agents"].items()},
        )

    def test_switching_from_qwen_removes_variant(self):
        self.run_install("qwen3-8-27b")
        self.run_install("free")
        self.assert_profile("free")

    def test_profile_switching_in_both_directions(self):
        self.run_install("free")
        free_snapshot = {
            agent: (self.config / "agents" / f"{agent}.md").read_bytes() for agent in ALL_AGENTS
        }
        self.run_install("gpt")
        self.assert_profile("gpt")
        self.run_install("free")
        self.assert_profile("free")
        self.assertEqual(
            free_snapshot,
            {agent: (self.config / "agents" / f"{agent}.md").read_bytes() for agent in ALL_AGENTS},
        )

    def test_refuses_unowned_target(self):
        planner = self.config / "agents" / "planner.md"
        planner.parent.mkdir(parents=True)
        planner.write_text("user-owned planner\n")
        result = self.run_install("free", check=False)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("Refusing to overwrite unowned file", result.stderr)
        self.assertEqual("user-owned planner\n", planner.read_text())
        self.assertFalse((self.config / ".opencode-pipeline-manifest.json").exists())
        self.assertFalse((self.config / "agents" / "pipeline.md").exists())

    def test_refuses_modified_owned_target(self):
        self.run_install("free")
        planner = self.config / "agents" / "planner.md"
        planner.write_text(planner.read_text() + "\nuser modification\n")
        before = self.snapshot_installation()
        result = self.run_install("gpt", check=False)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("Refusing to overwrite modified pipeline file", result.stderr)
        self.assertEqual(before, self.snapshot_installation())

    def test_refuses_target_symlink(self):
        outside = self.root / "outside-planner.md"
        outside.write_text("outside\n")
        planner = self.config / "agents" / "planner.md"
        planner.parent.mkdir(parents=True)
        planner.symlink_to(outside)
        result = self.run_install("free", check=False)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("Refusing target symlink", result.stderr)
        self.assertTrue(planner.is_symlink())
        self.assertEqual("outside\n", outside.read_text())
        self.assertFalse((self.config / ".opencode-pipeline-manifest.json").exists())

    def test_mid_switch_failure_restores_previous_installation(self):
        self.run_install("free")
        before = self.snapshot_installation()
        result = self.run_install("gpt", failure_after=4, check=False)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("Injected failure", result.stderr)
        self.assertEqual(before, self.snapshot_installation())
        self.assert_no_transaction_temps()

    def test_fresh_failure_leaves_no_partial_installation(self):
        result = self.run_install("free", failure_after=4, check=False)
        self.assertNotEqual(0, result.returncode)
        for path in self.installed_paths():
            self.assertFalse(path.exists(), path)
        self.assert_no_transaction_temps()

    def test_user_configuration_and_unrelated_files_are_unchanged(self):
        opencode_json = self.config / "opencode.json"
        unrelated_agent = self.config / "agents" / "custom.md"
        unrelated_plugin = self.config / "plugins" / "custom.js"
        unrelated_script = self.config / "scripts" / "custom.sh"
        files = {
            opencode_json: b'{"default_agent":"build"}\n',
            unrelated_agent: b"custom agent\n",
            unrelated_plugin: b"export default async () => ({})\n",
            unrelated_script: b"#!/bin/sh\nexit 0\n",
        }
        for path, content in files.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        before = {path: path.read_bytes() for path in files}
        self.run_install("free")
        self.run_install("gpt")
        self.assertEqual(before, {path: path.read_bytes() for path in files})


if __name__ == "__main__":
    unittest.main(verbosity=2)
