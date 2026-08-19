# OpenCode Multi-Agent Pipeline

A reusable eight-phase coding pipeline for [OpenCode](https://opencode.ai). Agent names represent stable roles; model providers are selected through profiles.

```text
clarify(planner) -> review-plan(debater) -> implement(implementer)
-> review-code(reviewer) -> security-review(security-reviewer)
-> test(tester) -> lint(linter) -> commit-msg(commit-msg)
```

Only `implementer` can modify source files. The `pipeline` primary agent orchestrates all role subagents.

## Optional Persistent Context

The fixed coding phases remain independent of any memory implementation. An
optional `context-manager` hook runs before planning and at meaningful
milestones. It loads `coding-context-okf` when that skill is installed and
otherwise reports `unavailable` without stopping or rerouting the pipeline.

```text
bootstrap? -> clarify -> review-plan -> checkpoint-plan?
-> implement -> checkpoint-implementation? -> review-code -> security-review
-> test -> lint -> checkpoint-verification? -> commit-msg -> finalize?
```

Install the context skill separately if you want these hooks:

```bash
npx skills add vVasile29/coding-agent-skills --skill coding-context-okf
```

The context manager is the only pipeline role that loads the skill. It places a
bounded handoff in `.opencode-workflow-state.md`; phase agents do not load vault
histories or topic directories themselves. Context errors are non-fatal, and
both repositories continue to work independently.

For source isolation, automatic context writes are allowed only below a path
matching `**/Engineering Context/repositories/**`. The default skill path works
without extra pipeline configuration. A custom path with a different directory
name is reported as blocked rather than broadening the role's write access.

## Install

Install the free-model profile:

```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/install.sh | bash -s -- free
```

Install the GPT-5.6 profile:

```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/install.sh | bash -s -- gpt
```

Install the local Ollama Qwen 3.8 27B profile:

```bash
ollama pull qwen3.8:27b
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/install.sh | bash -s -- qwen3-8-27b
```

The Qwen profile expects OpenCode to expose the model as `ollama/qwen3.8:27b` with `low`, `medium`, and `high` variants. If Ollama is not already configured as an OpenCode provider, add this to your global `~/.config/opencode/opencode.json` (merging it with any existing configuration):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (local)",
      "options": {
        "baseURL": "http://localhost:11434/v1"
      },
      "models": {
        "qwen3.8:27b": {
          "name": "Qwen 3.8 27B (local)",
          "reasoning": true,
          "limit": {
            "context": 262144,
            "output": 65536
          },
          "variants": {
            "low": {
              "reasoningEffort": "low"
            },
            "medium": {
              "reasoningEffort": "medium"
            },
            "high": {
              "reasoningEffort": "high"
            }
          }
        }
      }
    }
  }
}
```

OpenCode recommends at least a 64K context window for local models. Configure Ollama accordingly before launching OpenCode, for example with `OLLAMA_CONTEXT_LENGTH=65536 ollama serve`.

The profile selects reasoning variants by role: high for context management, planning, debate, implementation, review, and security review; medium for orchestration and testing; and low for linting and commit messages. OpenCode resolves each variant to its configured `reasoningEffort` and passes it to Ollama as `reasoning_effort`.

Restart OpenCode after installation, press **Tab**, and select `pipeline`. The installer does not change `default_agent` or rewrite `opencode.json`/`opencode.jsonc`.

Re-run the same command with a different profile to switch models. The canonical agent names stay unchanged, and OpenCode must be restarted after every profile switch.

## Profiles

| Role | Free profile | GPT profile | Qwen 3.8 27B profile |
| --- | --- | --- | --- |
| `pipeline` | Big Pickle | GPT-5.6 Terra, medium | Qwen 3.8 27B (Ollama), medium |
| `context-manager` | Big Pickle | GPT-5.6 Sol, medium | Qwen 3.8 27B (Ollama), high |
| `planner` | Big Pickle | GPT-5.6 Sol, high | Qwen 3.8 27B (Ollama), high |
| `debater` | MiMo V2.5 Free | GPT-5.6 Terra, medium | Qwen 3.8 27B (Ollama), high |
| `implementer` | DeepSeek V4 Flash Free | GPT-5.6 Sol, medium | Qwen 3.8 27B (Ollama), high |
| `reviewer` | Big Pickle | GPT-5.6 Terra, medium | Qwen 3.8 27B (Ollama), high |
| `security-reviewer` | Big Pickle | GPT-5.6 Sol, high | Qwen 3.8 27B (Ollama), high |
| `tester` | Big Pickle | GPT-5.6 Luna, low | Qwen 3.8 27B (Ollama), medium |
| `linter` | Big Pickle | GPT-5.6 Luna, low | Qwen 3.8 27B (Ollama), low |
| `commit-msg` | Big Pickle | GPT-5.6 Luna, low | Qwen 3.8 27B (Ollama), low |

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

At runtime the plugin adds exact `task` denies for the nine protected subagent names: the eight phase roles plus `context-manager`. It preserves every unrelated user task rule and moves the exact pipeline-role denies after all existing rules so OpenCode's last-match-wins evaluation cannot be overridden by an earlier role entry or later wildcard. No wildcard role names or model-specific permission rules are needed.

The `pipeline` agent has a local wildcard denial followed by exact allows for the nine protected roles, so it can launch exactly the pipeline workflow and optional context hook. Every role agent has a complete `task: deny`, preventing it from launching generic, exploratory, pipeline, or custom subagents. Ordinary non-pipeline primary agents cannot launch the protected role agents.

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
├── agents/                         orchestrator, eight phase roles, and optional context hook
├── models/profiles/
│   ├── free.json                   free-model assignments
│   ├── gpt.json                    GPT-5.6 assignments
│   └── qwen3-8-27b.json            local Ollama Qwen 3.8 27B assignments
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
