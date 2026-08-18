#!/usr/bin/env bash
# install-gpt.sh — Installs the GPT-powered pipeline alongside the free pipeline
# Installs pipeline-gpt (primary) + 8 GPT subagents into ~/.config/opencode/agents/
# Usage: curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/install-gpt.sh | bash
set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
AGENTS_DIR="$CONFIG_DIR/agents"
MANIFEST="$CONFIG_DIR/.opencode-pipeline-gpt-manifest.json"
BACKUP="$CONFIG_DIR/.opencode-pipeline-config-backup.json"
CONFIG_FILE="$CONFIG_DIR/opencode.json"
GITIGNORE_MARKER="$CONFIG_DIR/.opencode-pipeline-gitignore-owned"

GPT_AGENTS=("pipeline-gpt.md" "planner-gpt.md" "debater-gpt.md" "implementer-gpt.md" "reviewer-gpt.md" "security-reviewer-gpt.md" "tester-gpt.md" "linter-gpt.md" "commit-msg-gpt.md")

echo "==> Installing GPT Pipeline alongside your existing free pipeline"
echo "    Target: $AGENTS_DIR"
echo ""

mkdir -p "$AGENTS_DIR"

# 1. Download GPT agent files
echo "==> Downloading GPT agents..."
INSTALLED_JSON=""
for f in "${GPT_AGENTS[@]}"; do
  curl -fsSL "$REPO_URL/gpt/$f" -o "$AGENTS_DIR/$f"
  INSTALLED_JSON="$INSTALLED_JSON\"$f\","
  echo "    ✓ agents/$f"
done
INSTALLED_JSON="[${INSTALLED_JSON%,}]"

# 2. Reserve pipeline role agents for orchestrators
echo "==> Configuring GPT pipeline permissions..."
python3 -c "
import json, os, shutil

config_file = '$CONFIG_FILE'
backup_file = '$BACKUP'
pipeline_agent_patterns = (
    'planner*', 'debater*', 'implementer*', 'reviewer*',
    'security-reviewer*', 'tester*', 'linter*', 'commit-msg*'
)

if os.path.exists(config_file):
    with open(config_file) as f:
        config = json.load(f)
    manifest_version = 0
    if os.path.exists('$MANIFEST'):
        with open('$MANIFEST') as f:
            manifest_version = json.load(f).get('version', 1)
    if not os.path.exists(backup_file) and manifest_version < 2 and not os.path.exists('$CONFIG_DIR/.opencode-pipeline-manifest.json'):
        shutil.copy2(config_file, backup_file)
        print('    backed up existing config')
else:
    config = {}

permission = config.get('permission', {})
if isinstance(permission, str):
    permission = {'*': permission}
task = permission.get('task', {})
if isinstance(task, str):
    task = {'*': task}
# Role denies follow broad rules because the last matching permission wins.
for pattern in pipeline_agent_patterns:
    task.pop(pattern, None)
    task[pattern] = 'deny'
permission['task'] = task
config['permission'] = permission

with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\\n')

print('    pipeline role agents reserved for pipeline orchestrators')
"

# 3. Optionally set pipeline-gpt as default (skip if non-interactive / pipe mode)
echo ""
if [[ -t 0 ]]; then
  DEFAULT=""
  read -r -p "Set pipeline-gpt as your default agent? [y/N] " DEFAULT
  if [[ "$DEFAULT" =~ ^[Yy] ]]; then
    python3 -c "
import json, os
config_file = '$CONFIG_FILE'
if os.path.exists(config_file):
    with open(config_file) as f:
        config = json.load(f)
else:
    config = {}
config['default_agent'] = 'pipeline-gpt'
with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')
print('    default_agent set to pipeline-gpt')
"
  fi
else
  echo "    (non-interactive — skipping default_agent prompt)"
  echo "    To set as default later: opencode.json → \"default_agent\": \"pipeline-gpt\""
fi

# 4. Write manifest (use temp file to avoid heredoc/stdin conflict in pipe mode)
echo "==> Writing manifest..."
python3 -c "
import json, datetime
manifest = {
    'version': 2,
    'installed_at': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'files': $INSTALLED_JSON
}
with open('$MANIFEST', 'w') as f:
    json.dump(manifest, f, indent=2)
print('    manifest written')
"

# 5. Ensure state file is gitignored
GITIGNORE="$CONFIG_DIR/.gitignore"
if ! grep -q 'opencode-workflow-state' "$GITIGNORE" 2>/dev/null; then
  echo ".opencode-workflow-state.md" >> "$GITIGNORE" 2>/dev/null || true
  touch "$GITIGNORE_MARKER"
  echo "==> Added .opencode-workflow-state.md to global gitignore"
fi

echo ""
echo "==> ✓ GPT Pipeline installed!"
echo ""
echo "    Both pipelines are now available in opencode's agent selector (Tab key):"
echo "      • pipeline      — free OpenCode Zen models"
echo "      • pipeline-gpt — your paid OpenAI models"
echo ""
echo "    To switch, press Tab in the opencode TUI and select pipeline-gpt."
echo "    Or set it as default: opencode.json → \"default_agent\": \"pipeline-gpt\""
echo ""
echo "    To uninstall:"
echo "      curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/uninstall-gpt.sh | bash"
