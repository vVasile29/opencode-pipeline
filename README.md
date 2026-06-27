# OpenCode Multi-Agent Pipeline

A reusable 8-agent coding pipeline for [OpenCode](https://opencode.ai). Installs in your global config so every project inherits it.

**Phases:** clarify(planner) → review-plan(debater) → implement(implementer) → review-code(reviewer) → security-review(security-reviewer) → test(tester) → lint(linter) → commit-msg(commit-msg)

Only the **implementer** can touch source files. All other agents are read-only — the debater critiques plans, the reviewer inspects diffs, the tester runs tests, etc.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/install.sh | bash
```

Then `cd` into any project and run `opencode`. The pipeline agent is now your default.

## Usage

```bash
cd /your/project
opencode
```

Then describe what you want built:

> *"Add a due-date field to tasks and an 'overdue' command."*

The pipeline reads the request → plans → debates → implements → reviews → security-audits → tests → lints → drafts a commit message — all with different specialized models.

## Selecting Models

The pipeline uses OpenCode Zen free models by default. Models change over time — swap them anytime:

### Interactive (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/select-models.sh | bash
```

Uses `fzf` (if available) to let you pick a model for each role from the current free pool.

### Auto-select

```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/auto-select-models.sh | bash
```

Scores every free model by capability and assigns the best fit to each role automatically.

## Model Availability

Free models change constantly — providers deprecate them, rate-limit them, or rotate their offerings. The pipeline handles this gracefully:

### During a session
If a subagent's model returns a quota/rate-limit error, the pipeline tells you which agent failed and suggests a fallback command. Swap the model without restarting `opencode`:

```bash
# See which agent failed, then swap it
opencode-pipeline-fallback tester

# Or let it pick the next best automatically
opencode-pipeline-fallback --auto planner

# Check all current models
opencode-pipeline-fallback --list
```

After swapping, tell the pipeline to retry. It re-reads the state file and continues from where it left off.

### If the pipeline agent itself fails
No orchestrator remains to suggest a fallback. Fix from your terminal:

```bash
opencode-pipeline-fallback --auto pipeline
opencode
```

The session's `.opencode-workflow-state.md` persists in the project directory, so the new run picks up where it left off.

### After a provider rotates free models
Re-optimize all roles at once:

```bash
# Automatic — scores and assigns the best fit
auto-select-models.sh
```

### Manually
Agent files are plain markdown — edit the `model:` line directly:

```bash
nano ~/.config/opencode/agents/planner.md
# Change: model: opencode/big-pickle → model: opencode/new-model-name
```

### Install and uninstall are unaffected
The install/uninstall scripts never call model APIs or read the models cache. They only copy files into your config directory. A deprecated model doesn't block install or uninstall.

### If the models cache is stale
`opencode-pipeline-fallback` and `auto-select-models.sh` read from `~/.cache/opencode/models.json`. Run `opencode` once to refresh it if you see stale options.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/uninstall.sh | bash
```

Removes all pipeline agents and restores your original `opencode.json`.

## Architecture

| Role | Model (default) | Permissions | Responsibility |
|------|----------------|-------------|----------------|
| **pipeline** | Big Pickle | task whitelist, read-only | Orchestrates the 8-phase handoff |
| **planner** | Big Pickle | edit: deny, bash: deny | Clarifies scope, writes plan |
| **debater** | Nemotron 3 Ultra Free | edit: deny, bash: deny | Critiques plan (different model) |
| **implementer** | DeepSeek V4 Flash Free | edit: allow, bash: allow | **Only agent that writes code** |
| **reviewer** | Big Pickle | edit: deny, bash: deny | Reviews diff for correctness |
| **security-reviewer** | Big Pickle | edit: deny, bash: deny | Audits code for vulnerabilities |
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

## Examples

### Swap a failing agent's model

When a subagent hits a quota/rate-limit error, the pipeline tells you which one failed. Swap its model interactively:

```bash
# Interactive: pick an agent, then pick a model from the free pool
opencode-pipeline-fallback

# Or pick a model for a specific agent
opencode-pipeline-fallback tester

# Non-interactive: auto-assign the next best free model
opencode-pipeline-fallback --auto planner

# Show all agents and their current models
opencode-pipeline-fallback --list
```

### Re-assign all models

After providers rotate their free models, re-optimize the whole pipeline:

```bash
# Interactive (fzf per role)
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/select-models.sh | bash

# Fully automatic (capability scoring)
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/auto-select-models.sh | bash
```

### Full workflow

```bash
# 1. Install (one time)
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/install.sh | bash

# 2. Open a project and describe what to build
cd ~/my-project
opencode

# Pipeline output:
#   Planner → writes a plan
#   Debater → critiques and approves
#   Implementer → writes code
#   Reviewer → checks the diff
#   Security Reviewer → audits for vulnerabilities
#   Tester → runs tests
#   Linter → checks style
#   Commit Message → drafts a commit

# 3. If a step fails with quota, swap its model
opencode-pipeline-fallback implementer

# 4. Tell the pipeline to retry
#    (it will pick up where it left off)
```

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
│   ├── security-reviewer.md   ← subagent
│   ├── tester.md              ← subagent
│   ├── linter.md              ← subagent
│   └── commit-msg.md          ← subagent
└── .opencode-pipeline-manifest.json  ← tracks installed files for clean uninstall
```

## License

MIT
