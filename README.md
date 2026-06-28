# OpenCode Multi-Agent Pipeline

A reusable multi-agent coding pipeline for [OpenCode](https://opencode.ai). Installs in your global config so every project inherits it.

**Two variants available:**

| Pipeline | Models | Cost | When to use |
|----------|--------|------|-------------|
| **pipeline** (free) | OpenCode Zen free models | Free | Daily driver |
| **pipeline-gpt** (paid) | Your OpenAI GPT models | Your API costs | When free quota exhausted, or for higher quality |

Both install side-by-side. Switch between them in the opencode TUI via the **Tab key**.

**Phases (both pipelines):** clarify(planner) → review-plan(debater) → implement(implementer) → review-code(reviewer) → security-review(security-reviewer) → test(tester) → lint(linter) → commit-msg(commit-msg)

Only the **implementer** can touch source files. All other agents are read-only — the debater critiques plans, the reviewer inspects diffs, the tester runs tests, etc.

---

## Quick Install

### Free pipeline only
```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/install.sh | bash
```

### GPT pipeline (paid, adds alongside free)
```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/install-gpt.sh | bash
```

Then `cd` into any project and run `opencode`. The pipeline agent is now your default.

---

## Usage

```bash
cd /your/project
opencode
```

Then describe what you want built:

> *"Add a due-date field to tasks and an 'overdue' command."*

The pipeline reads the request → plans → debates → implements → reviews → security-audits → tests → lints → drafts a commit message — all with different specialized models.

### Switching pipelines

**Via TUI (recommended):**
1. Run `opencode`
2. Press **Tab** to open the agent selector
3. Pick **pipeline** (free) or **pipeline-gpt** (paid)
4. Describe your task

**Via config:**
```bash
# Set GPT as your default
opencode.json → "default_agent": "pipeline-gpt"

# Revert to free
opencode.json → "default_agent": "pipeline"
```

---

## Selecting Models

### Free pipeline models
The free pipeline uses OpenCode Zen free models by default. Models change over time — swap them anytime:

**Interactive (recommended):**
```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/select-models.sh | bash
```
Uses `fzf` (if available) to let you pick a model for each role from the current free pool.

**Auto-select:**
```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/auto-select-models.sh | bash
```
Scores every free model by capability and assigns the best fit to each role automatically.

### GPT pipeline models
The GPT pipeline is pre-configured with your OpenAI models. To change assignments:

**Interactive:**
```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/select-gpt-models.sh | bash
```
Lists all OpenAI models from your opencode cache and lets you pick per role.

**Or edit agent files directly:**
```bash
# Edit model field in any agent file
~/.config/opencode/agents/planner-gpt.md    → model: openai/gpt-5.5
~/.config/opencode/agents/tester-gpt.md     → model: openai/gpt-5.4-mini
```

---

## Default Assignments

### Free pipeline (pipeline)

| Role | Model | Responsibility |
|------|-------|----------------|
| **pipeline** | Big Pickle | Orchestrates the 8-phase handoff |
| **planner** | Big Pickle | Clarifies scope, writes plan |
| **debater** | Nemotron 3 Ultra Free | Critiques plan (different model) |
| **implementer** | DeepSeek V4 Flash Free | **Only agent that writes code** |
| **reviewer** | Big Pickle | Reviews diff for correctness |
| **security-reviewer** | Big Pickle | Audits code for vulnerabilities |
| **tester** | North Mini Code Free | Runs test suite |
| **linter** | North Mini Code Free | Runs lint checks |
| **commit-msg** | North Mini Code Free | Drafts conventional commit |

### GPT pipeline (pipeline-gpt)

| Role | Model | Reasoning Effort | Responsibility |
|------|-------|-----------------|----------------|
| **pipeline-gpt** | GPT-5.5 | medium | Orchestrates the 8-phase handoff |
| **planner-gpt** | GPT-5.5 | high | Clarifies scope, writes plan |
| **debater-gpt** | GPT-5.5 | medium | Critiques plan (diverse perspective) |
| **implementer-gpt** | GPT-5.5 | medium | **Only agent that writes code** |
| **reviewer-gpt** | GPT-5.5 | medium | Reviews diff for correctness |
| **security-reviewer-gpt** | GPT-5.5 | high | Audits code for vulnerabilities |
| **tester-gpt** | GPT-5.4 mini | low | Runs test suite |
| **linter-gpt** | GPT-5.4 mini | low | Runs lint checks |
| **commit-msg-gpt** | GPT-5.4 mini | low | Drafts conventional commit |

---

## Architecture

Both pipelines follow the same pattern. The GPT variant uses the `-gpt` suffix on all agent names:

```
~/.config/opencode/
├── opencode.json              ← sets default_agent (pick "pipeline" or "pipeline-gpt")
├── agents/
│   ├── pipeline.md            ← free orchestrator (primary)
│   ├── planner.md             ← free subagent
│   ├── ...
│   ├── commit-msg.md          ← free subagent
│   ├── pipeline-gpt.md        ← GPT orchestrator (primary)
│   ├── planner-gpt.md         ← GPT subagent
│   ├── ...
│   └── commit-msg-gpt.md      ← GPT subagent
├── .opencode-pipeline-manifest.json      ← tracks free pipeline files
└── .opencode-pipeline-gpt-manifest.json  ← tracks GPT pipeline files
```

## Uninstall

### Free pipeline only
```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/uninstall.sh | bash
```

### GPT pipeline only
```bash
curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/uninstall-gpt.sh | bash
```
Leaves the free pipeline intact.

### Both pipelines
Run both uninstall commands above.

---

## Files in this repo

```
opencode-pipeline/
├── opencode.json              ← default_agent config (merged at install)
├── README.md
├── .gitignore
├── install.sh                 ← installs free pipeline
├── uninstall.sh               ← removes free pipeline
├── install-gpt.sh             ← installs GPT pipeline (alongside free)
├── uninstall-gpt.sh           ← removes GPT pipeline only
├── select-models.sh           ← interactive model picker for free pipeline
├── auto-select-models.sh      ← automatic model assigner for free pipeline
├── select-gpt-models.sh       ← interactive model picker for GPT pipeline
├── agents/                    ← free pipeline agent definitions
│   ├── pipeline.md
│   ├── planner.md
│   ├── debater.md
│   ├── implementer.md
│   ├── reviewer.md
│   ├── security-reviewer.md
│   ├── tester.md
│   ├── linter.md
│   └── commit-msg.md
├── gpt/                       ← GPT pipeline agent definitions
│   ├── pipeline-gpt.md
│   ├── planner-gpt.md
│   ├── debater-gpt.md
│   ├── implementer-gpt.md
│   ├── reviewer-gpt.md
│   ├── security-reviewer-gpt.md
│   ├── tester-gpt.md
│   ├── linter-gpt.md
│   └── commit-msg-gpt.md
└── models/
    ├── assign_models.py       ← capability-scoring algorithm
    └── roles.json             ← role requirements for scoring
```

## License

MIT
