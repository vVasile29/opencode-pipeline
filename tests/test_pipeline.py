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
PHASE_ROLES = (
    "planner",
    "debater",
    "implementer",
    "reviewer",
    "security-reviewer",
    "tester",
    "linter",
    "commit-msg",
)
ROLES = ("context-manager",) + PHASE_ROLES
ALL_AGENTS = ("pipeline",) + ROLES
PLUGIN_RELATIVE = "plugins/opencode-pipeline-permissions.js"
PROFILE_RELATIVE = ".opencode-pipeline-profile.json"


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

    def run_uninstall(self, *, check=True):
        return subprocess.run(
            ["bash", str(ROOT / "uninstall.sh")],
            cwd=ROOT,
            env=self.environment,
            text=True,
            capture_output=True,
            check=check,
        )

    def run_switch(self, profile, *, check=True):
        return subprocess.run(
            ["bash", str(ROOT / "switch-profile.sh"), profile],
            cwd=ROOT,
            env=self.environment,
            text=True,
            capture_output=True,
            check=check,
        )

    def run_selector(self, model, *, all_roles=False, check=True):
        binary_directory = self.root / "bin"
        binary_directory.mkdir(exist_ok=True)
        opencode = binary_directory / "opencode"
        opencode.write_text(f"#!/bin/sh\nprintf '%s\\n' '{model}'\n")
        opencode.chmod(0o755)
        fzf = binary_directory / "fzf"
        fzf.write_text(f"#!/bin/sh\nwhile IFS= read -r line; do :; done\nprintf '%s\\n' '{model}'\n")
        fzf.chmod(0o755)
        environment = self.environment.copy()
        environment["PATH"] = f"{binary_directory}{os.pathsep}{environment['PATH']}"
        command = ["bash", str(ROOT / "select-models.sh")]
        if all_roles:
            command.append(model)
        return subprocess.run(
            command,
            cwd=ROOT,
            env=environment,
            text=True,
            capture_output=True,
            check=check,
        )

    def installed_paths(self):
        return [self.config / "agents" / f"{agent}.md" for agent in ALL_AGENTS] + [
            self.config / PLUGIN_RELATIVE,
            self.config / PROFILE_RELATIVE,
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
        active_profile = json.loads((self.config / PROFILE_RELATIVE).read_text())
        self.assertEqual(4, manifest["version"])
        self.assertEqual(profile_name, manifest["profile"])
        self.assertEqual(12, len(manifest["files"]))
        self.assertEqual(profile, active_profile)
        for agent in profile["agents"]:
            content = frontmatter(self.config / "agents" / f"{agent}.md")
            self.assertNotIn("\nmodel:", content)
            self.assertNotIn("\nvariant:", content)
        runtime_config = self.apply_plugin([{}], profile=profile)[0]
        for agent, settings in profile["agents"].items():
            self.assertEqual(settings["model"], runtime_config["agent"][agent]["model"])
            self.assertEqual(settings.get("variant"), runtime_config["agent"][agent].get("variant"))
        for relative, expected in manifest["files"].items():
            path = self.config / relative
            self.assertTrue(path.is_file())
            self.assertFalse(path.is_symlink())
            self.assertEqual(expected, sha256(path))

    def apply_plugin(self, configs, *, profile=None):
        if profile is None:
            profile = json.loads((ROOT / "models" / "profiles" / "free.json").read_text())
        script = """
const factory = (await import(process.argv[1])).default
const payload = JSON.parse(await new Promise((resolve) => {
  let data = ""
  process.stdin.setEncoding("utf8")
  process.stdin.on("data", (chunk) => data += chunk)
  process.stdin.on("end", () => resolve(data))
}))
const configs = payload.configs
const hooks = await factory(undefined, { profile: payload.profile })
for (const config of configs) hooks.config(config)
process.stdout.write(JSON.stringify(configs))
"""
        result = subprocess.run(
            ["node", "--input-type=module", "-e", script, (ROOT / "plugins" / "opencode-pipeline-permissions.js").as_uri()],
            input=json.dumps({"configs": configs, "profile": profile}),
            text=True,
            capture_output=True,
            check=True,
        )
        return json.loads(result.stdout)

    def apply_runtime_hooks(self, calls):
        profile = json.loads((ROOT / "models" / "profiles" / "free.json").read_text())
        script = """
const factory = (await import(process.argv[1])).default
const payload = JSON.parse(await new Promise((resolve) => {
  let data = ""
  process.stdin.setEncoding("utf8")
  process.stdin.on("data", (chunk) => data += chunk)
  process.stdin.on("end", () => resolve(data))
}))
const calls = payload.calls
const hooks = await factory(undefined, { profile: payload.profile })
for (const call of calls) {
  await hooks[call.hook](call.input, call.output)
}
process.stdout.write(JSON.stringify(calls))
"""
        result = subprocess.run(
            [
                "node",
                "--input-type=module",
                "-e",
                script,
                (ROOT / "plugins" / "opencode-pipeline-permissions.js").as_uri(),
            ],
            input=json.dumps({"calls": calls, "profile": profile}),
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

    def test_plugin_applies_profile_without_replacing_agent_definitions(self):
        config = {
            "agent": {
                "planner": {
                    "description": "Canonical planner description",
                    "temperature": 0.1,
                    "variant": "stale",
                }
            }
        }
        result = self.apply_plugin([config])[0]
        planner = result["agent"]["planner"]
        self.assertEqual("Canonical planner description", planner["description"])
        self.assertEqual(0.1, planner["temperature"])
        self.assertEqual("opencode/big-pickle", planner["model"])
        self.assertNotIn("variant", planner)

    def test_canonical_agent_sources_are_model_agnostic(self):
        for agent in ALL_AGENTS:
            content = frontmatter(ROOT / "agents" / f"{agent}.md")
            self.assertNotIn("\nmodel:", content, agent)
            self.assertNotIn("\nvariant:", content, agent)

    def test_plugin_injects_session_state_into_pipeline_and_phase_tasks(self):
        calls = self.apply_runtime_hooks(
            [
                {
                    "hook": "chat.message",
                    "input": {"sessionID": "ses_first", "agent": "pipeline"},
                    "output": {"message": {}, "parts": [{"type": "text", "text": "Fix it"}]},
                },
                {
                    "hook": "tool.execute.before",
                    "input": {"tool": "task", "sessionID": "ses_first", "callID": "call_1"},
                    "output": {
                        "args": {
                            "subagent_type": "planner",
                            "prompt": "Clarify the request",
                        }
                    },
                },
                {
                    "hook": "chat.message",
                    "input": {"sessionID": "ses_second"},
                    "output": {
                        "message": {"agent": "pipeline"},
                        "parts": [{"type": "text", "text": "Fix another"}],
                    },
                },
            ]
        )

        first_message = calls[0]["output"]["parts"][0]["text"]
        phase_prompt = calls[1]["output"]["args"]["prompt"]
        second_message = calls[2]["output"]["parts"][0]["text"]
        self.assertIn(".opencode-workflow-state-ses_first.md", first_message)
        self.assertIn(".opencode-workflow-state-ses_first.md", phase_prompt)
        self.assertIn(".opencode-workflow-state-ses_second.md", second_message)
        self.assertNotIn(".opencode-workflow-state-ses_second.md", first_message)

    def test_plugin_leaves_unrelated_agents_and_tasks_unchanged(self):
        calls = [
            {
                "hook": "chat.message",
                "input": {"sessionID": "ses_other", "agent": "build"},
                "output": {"message": {}, "parts": [{"type": "text", "text": "Build it"}]},
            },
            {
                "hook": "tool.execute.before",
                "input": {"tool": "task", "sessionID": "ses_other", "callID": "call_2"},
                "output": {
                    "args": {
                        "subagent_type": "explore",
                        "prompt": "Explore the repository",
                    }
                },
            },
        ]
        self.assertEqual(calls, self.apply_runtime_hooks(calls))

    def test_pipeline_uses_only_session_specific_state_files(self):
        pipeline = (ROOT / "agents" / "pipeline.md").read_text()
        self.assertIn('"**/.opencode-workflow-state-*.md": allow', frontmatter(ROOT / "agents" / "pipeline.md"))
        self.assertNotIn('"**/.opencode-workflow-state.md": allow', frontmatter(ROOT / "agents" / "pipeline.md"))
        self.assertIn("session-specific `.opencode-workflow-state-<session-id>.md`", pipeline)
        for agent in ALL_AGENTS:
            content = (ROOT / "agents" / f"{agent}.md").read_text()
            self.assertNotIn("workflow state file (`.opencode-workflow-state.md`", content, agent)

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

    def test_context_manager_is_scoped_to_optional_context(self):
        content = (ROOT / "agents" / "context-manager.md").read_text()
        permissions = frontmatter(ROOT / "agents" / "context-manager.md")
        self.assertIn('  edit:\n    "*": deny\n    "**/Engineering Context/repositories/**": allow', permissions)
        self.assertIn('  bash:\n    "*": deny', permissions)
        self.assertNotIn('"git diff *": allow', permissions)
        self.assertNotIn('"git log *": allow', permissions)
        self.assertIn('  skill:\n    "*": deny\n    coding-context-okf: allow', permissions)
        self.assertIn("  external_directory: allow", permissions)
        self.assertIn("Never modify project source", content)
        self.assertIn("Context failures are non-fatal", content)

    def test_pipeline_declares_non_fatal_context_hooks(self):
        content = (ROOT / "agents" / "pipeline.md").read_text()
        for operation in (
            "bootstrap",
            "checkpoint-plan",
            "checkpoint-implementation",
            "checkpoint-verification",
            "finalize",
        ):
            self.assertIn(f"`{operation}`", content)
        self.assertIn("non-fatal hooks, not coding phases", content)
        self.assertIn("skip all", content)
        self.assertIn("remaining context hooks", content)
        self.assertIn("before the first planner", content)

    def test_reviewer_routes_through_security_review(self):
        content = (ROOT / "agents" / "reviewer.md").read_text()
        self.assertIn("**Next agent**: security-reviewer (if approved)", content)
        self.assertNotIn("**Next agent**: tester (if approved)", content)

    def test_fresh_free_profile_installation(self):
        self.run_install("free")
        self.assert_profile("free")

    def test_fresh_gpt_profile_installation(self):
        self.run_install("gpt")
        self.assert_profile("gpt")

    def test_fresh_gpt_oss_120b_profile_installation(self):
        self.run_install("gpt-oss-120b")
        self.assert_profile("gpt-oss-120b")
        profile = json.loads((ROOT / "models" / "profiles" / "gpt-oss-120b.json").read_text())
        self.assertEqual(
            {
                "pipeline": "medium",
                "context-manager": "high",
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

    def test_fresh_qwen3_8_27b_profile_installation(self):
        self.run_install("qwen3-8-27b")
        self.assert_profile("qwen3-8-27b")
        profile = json.loads((ROOT / "models" / "profiles" / "qwen3-8-27b.json").read_text())
        self.assertEqual(
            {
                "pipeline": "medium",
                "context-manager": "high",
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

    def test_fresh_qwen3_coder_next_q8_profile_installation(self):
        self.run_install("qwen3-coder-next-q8")
        self.assert_profile("qwen3-coder-next-q8")
        profile = json.loads(
            (ROOT / "models" / "profiles" / "qwen3-coder-next-q8.json").read_text()
        )
        for settings in profile["agents"].values():
            self.assertEqual("ollama/qwen3-coder-next:q8_0", settings["model"])
            self.assertNotIn("variant", settings)

    def test_fresh_qwen3_5_122b_profile_installation(self):
        self.run_install("qwen3-5-122b")
        self.assert_profile("qwen3-5-122b")
        profile = json.loads((ROOT / "models" / "profiles" / "qwen3-5-122b.json").read_text())
        self.assertEqual(
            {
                "pipeline": "high",
                "context-manager": "high",
                "planner": "high",
                "debater": "high",
                "implementer": "high",
                "reviewer": "high",
                "security-reviewer": "high",
                "tester": "high",
                "linter": "none",
                "commit-msg": "none",
            },
            {agent: settings["variant"] for agent, settings in profile["agents"].items()},
        )

    def test_fresh_qwen3_8_27b_mtp_bf16_profile_installation(self):
        self.run_install("qwen3-8-27b-mtp-bf16")
        self.assert_profile("qwen3-8-27b-mtp-bf16")

    def test_quick_selector_assigns_one_model_to_every_role(self):
        model = "ollama/qwen3.8:27b-mtp-bf16"
        self.run_install("free")
        agents_before = {
            agent: (self.config / "agents" / f"{agent}.md").read_bytes() for agent in ALL_AGENTS
        }
        self.run_selector(model, all_roles=True)

        manifest = json.loads((self.config / ".opencode-pipeline-manifest.json").read_text())
        profile = json.loads((self.config / PROFILE_RELATIVE).read_text())
        self.assertEqual("custom", manifest["profile"])
        for agent in ALL_AGENTS:
            self.assertEqual(model, profile["agents"][agent]["model"])
            self.assertNotIn("variant", profile["agents"][agent])
        self.assertEqual(
            agents_before,
            {agent: (self.config / "agents" / f"{agent}.md").read_bytes() for agent in ALL_AGENTS},
        )
        for relative, expected in manifest["files"].items():
            self.assertEqual(expected, sha256(self.config / relative))

    def test_switching_from_qwen_removes_variant(self):
        self.run_install("qwen3-8-27b")
        self.run_switch("free")
        self.assert_profile("free")

    def test_custom_selector_updates_context_manager(self):
        self.run_install("free")
        agents_before = {
            agent: (self.config / "agents" / f"{agent}.md").read_bytes() for agent in ALL_AGENTS
        }
        self.run_selector("test/provider-model")
        manifest = json.loads((self.config / ".opencode-pipeline-manifest.json").read_text())
        profile = json.loads((self.config / PROFILE_RELATIVE).read_text())
        self.assertEqual("custom", manifest["profile"])
        for agent in ALL_AGENTS:
            self.assertEqual("test/provider-model", profile["agents"][agent]["model"])
            self.assertNotIn("variant", profile["agents"][agent])
        self.assertEqual(
            agents_before,
            {agent: (self.config / "agents" / f"{agent}.md").read_bytes() for agent in ALL_AGENTS},
        )

    def test_profile_switching_in_both_directions(self):
        self.run_install("free")
        free_snapshot = {
            agent: (self.config / "agents" / f"{agent}.md").read_bytes() for agent in ALL_AGENTS
        }
        self.run_switch("gpt")
        self.assert_profile("gpt")
        self.run_switch("free")
        self.assert_profile("free")
        self.assertEqual(
            free_snapshot,
            {agent: (self.config / "agents" / f"{agent}.md").read_bytes() for agent in ALL_AGENTS},
        )

    def test_install_migrates_version_3_manifest(self):
        self.run_install("free")
        manifest_path = self.config / ".opencode-pipeline-manifest.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["version"] = 3
        manifest["files"].pop(PROFILE_RELATIVE)
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        (self.config / PROFILE_RELATIVE).unlink()

        self.run_install("gpt")
        self.assert_profile("gpt")

    def test_profile_switch_refuses_modified_active_profile(self):
        self.run_install("free")
        profile_path = self.config / PROFILE_RELATIVE
        profile_path.write_text(profile_path.read_text() + "\n")
        agents_before = {
            agent: (self.config / "agents" / f"{agent}.md").read_bytes() for agent in ALL_AGENTS
        }

        result = self.run_switch("gpt", check=False)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("Refusing to overwrite modified pipeline profile", result.stderr)
        self.assertEqual(
            agents_before,
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

    def test_uninstall_removes_unchanged_context_manager(self):
        self.run_install("free")
        self.run_uninstall()
        for path in self.installed_paths():
            self.assertFalse(path.exists(), path)

    def test_uninstall_preserves_modified_context_manager(self):
        self.run_install("free")
        context_manager = self.config / "agents" / "context-manager.md"
        context_manager.write_text(context_manager.read_text() + "\nuser modification\n")
        result = self.run_uninstall()
        self.assertTrue(context_manager.exists())
        self.assertIn("preserved modified file", result.stdout)
        self.assertFalse((self.config / ".opencode-pipeline-manifest.json").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
