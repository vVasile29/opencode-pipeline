# OpenCode Multi-Agent Pipeline

A reusable 7-agent coding pipeline for [OpenCode](https://opencode.ai). Installs in your global config so every project inherits it.

**Phases:** clarify(planner) → review-plan(debater) → implement(implementer) → review-code(reviewer) → test(tester) → lint(linter) → commit-msg(commit-msg)

Only the **implementer** can touch source files. All other agents are read-only — the debater critiques plans, the reviewer inspects diffs, the tester runs tests, etc.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/main/install.sh | bash
```

Then `cd` into any project and run `opencode`. The pipeline agent is now your default.

## Usage

```bash
cd /your/project
opencode
```

Then describe what you want built:

> *"Add a due-date field to tasks and an 'overdue' command."*

The pipeline reads the request → plans → debates → implements → reviews → tests → lints → drafts a commit message — all with different specialized models.

## Selecting Models

The pipeline uses OpenCode Zen free models by default. Models change over time — swap them anytime:

### Interactive (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/main/select-models.sh | bash
```

Uses `fzf` (if available) to let you pick a model for each role from the current free pool.

### Auto-select

```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/main/auto-select-models.sh | bash
```

Scores every free model by capability and assigns the best fit to each role automatically.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/main/uninstall.sh | bash
```

Removes all pipeline agents and restores your original `opencode.json`.

## Architecture

| Role | Model (default) | Permissions | Responsibility |
|------|----------------|-------------|----------------|
| **pipeline** | Big Pickle | task whitelist, read-only | Orchestrates the 7-phase handoff |
| **planner** | Big Pickle | edit: deny, bash: deny | Clarifies scope, writes plan |
| **debater** | Nemotron 3 Ultra Free | edit: deny, bash: deny | Critiques plan (different model) |
| **implementer** | DeepSeek V4 Flash Free | edit: allow, bash: allow | **Only agent that writes code** |
| **reviewer** | Big Pickle | edit: deny, bash: deny | Reviews diff for correctness |
| **tester** | North Mini Code Free | bash: allow | Runs test suite |
| **linter** | North Mini Code Free | bash: allow | Runs lint checks |
| **commit-msg** | North Mini Code Free | bash: allow | Drafts conventional commit |

## Agent Files

All configuration is in `~/.config/opencode/agents/` — plain markdown with YAML frontmatter. Readable, editable, owned by you. No plugins, no third-party dependencies, no npm.

## How It Works

1. The **pipeline** primary agent reads `.opencode-workflow-state.md` in your project root
2. It invokes each subagent via the Task tool, passing a description of what to do
3. Each subagent reads the state file, does its work, writes its section, and sets the next agent
4. The pipeline reads the state file again to check routing before each handoff
5. If any agent routes back (e.g. reviewer → implementer), the pipeline follows that

## Files

```
~/.config/opencode/
├── opencode.json              ← sets default_agent: pipeline (merged, never replaced)
├── agents/
│   ├── pipeline.md            ← orchestrator (primary)
│   ├── planner.md             ← subagent
│   ├── debater.md             ← subagent
│   ├── implementer.md         ← subagent
│   ├── reviewer.md            ← subagent
│   ├── tester.md              ← subagent
│   ├── linter.md              ← subagent
│   └── commit-msg.md          ← subagent
└── .opencode-pipeline-manifest.json  ← tracks installed files for clean uninstall
```

## License

MIT
