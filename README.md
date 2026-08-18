# OpenCode Multi-Agent Pipeline

A reusable eight-phase coding pipeline for [OpenCode](https://opencode.ai). Agent names represent stable roles; model providers are selected through profiles.

```text
clarify(planner) -> review-plan(debater) -> implement(implementer)
-> review-code(reviewer) -> security-review(security-reviewer)
-> test(tester) -> lint(linter) -> commit-msg(commit-msg)
```

Only `implementer` can modify source files. The `pipeline` primary agent orchestrates all role subagents.

## Install

Install the free-model profile:

```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/install.sh | bash -s -- free
```

Install the GPT-5.6 profile:

```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/install.sh | bash -s -- gpt
```

Restart OpenCode after installation, press **Tab**, and select `pipeline`. The installer does not change `default_agent` or rewrite `opencode.json`/`opencode.jsonc`.

Re-run the same command with a different profile to switch models. The canonical agent names stay unchanged, and OpenCode must be restarted after every profile switch.

## Profiles

| Role | Free profile | GPT profile |
| --- | --- | --- |
| `pipeline` | Big Pickle | GPT-5.6 Terra, medium |
| `planner` | Big Pickle | GPT-5.6 Sol, high |
| `debater` | MiMo V2.5 Free | GPT-5.6 Terra, medium |
| `implementer` | DeepSeek V4 Flash Free | GPT-5.6 Sol, medium |
| `reviewer` | Big Pickle | GPT-5.6 Terra, medium |
| `security-reviewer` | Big Pickle | GPT-5.6 Sol, high |
| `tester` | Big Pickle | GPT-5.6 Luna, low |
| `linter` | Big Pickle | GPT-5.6 Luna, low |
| `commit-msg` | Big Pickle | GPT-5.6 Luna, low |

Profiles live under `models/profiles/`. Adding another provider, such as Qwen, requires only another profile; it does not require another set of agents.

## Custom Models

Use the provider-agnostic selector to assign any model reported by `opencode models`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/select-models.sh)
```

The selector updates the same canonical role files and marks the installed profile as `custom`.

## Permission Isolation

The installer adds one auto-discovered global plugin:

```text
~/.config/opencode/plugins/opencode-pipeline-permissions.js
```

At runtime the plugin adds exact `task` denies for the eight role names. It preserves every unrelated user task rule and moves the exact pipeline-role denies after all existing rules so OpenCode's last-match-wins evaluation cannot be overridden by an earlier role entry or later wildcard. No wildcard role names or model-specific permission rules are needed.

The `pipeline` agent has a local wildcard denial followed by exact allows for the eight roles, so it can launch exactly the pipeline workflow. Every role agent has a complete `task: deny`, preventing it from launching generic, exploratory, pipeline, or custom subagents. Ordinary non-pipeline primary agents cannot launch the protected role agents.

Role subagents are also hidden from autocomplete. OpenCode still permits direct user invocation where supported; task permissions enforce the model-driven orchestration boundary.

Removing the plugin removes the permission overlay. The user's persisted OpenCode configuration is never rewritten.

## Installation Safety

The installer downloads and validates everything in a temporary directory before writing global files. It refuses to overwrite:

- an agent or plugin it does not own;
- an installed pipeline file modified since installation;
- a legacy side-by-side GPT installation.

The ownership manifest stores file hashes, not configuration backups:

```text
~/.config/opencode/.opencode-pipeline-manifest.json
```

Profile switching is allowed only while the installed files still match the manifest. The custom model selector updates the hashes after intentional model changes.

Installation and profile switching use a rollback-capable transaction. New files and rollback copies are prepared on the destination filesystem, each target is replaced atomically, and the manifest is replaced last. Ordinary exceptions and handled `SIGINT`/`SIGTERM` interruptions restore every previous target and the previous manifest, or remove newly created targets during a failed fresh install.

This is not a claim of full crash consistency: `SIGKILL`, machine failure, power loss, or storage failure can stop the process without running rollback. Such failures may leave destination-local temporary files or a partially replaced installation requiring manual recovery.

## Upgrading The Legacy Dual Pipeline

The old `pipeline`/`pipeline-gpt` installation must be uninstalled before using this version. The new installer deliberately refuses to guess ownership of legacy files.

Use the uninstallers from the last dual-pipeline release, then install one canonical profile:

```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/784138b/uninstall-gpt.sh | bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/784138b/uninstall.sh | bash
```

Review `~/.config/opencode/scripts/` before running the legacy free uninstaller because that old release removes the whole directory.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/uninstall.sh | bash
```

Uninstall removes only unchanged files listed in the ownership manifest. Modified files are preserved and reported. Restart OpenCode afterward to unload the permission plugin.

## Repository Layout

```text
opencode-pipeline/
├── agents/                         canonical pipeline and role prompts
├── models/profiles/
│   ├── free.json                   free-model assignments
│   └── gpt.json                    GPT-5.6 assignments
├── plugins/
│   └── opencode-pipeline-permissions.js
├── tests/
│   └── test_pipeline.py              isolated permission and lifecycle regressions
├── install.sh                      install or switch a profile
├── uninstall.sh                    remove installer-owned files
└── select-models.sh                choose any available model per role
```

## License

MIT
