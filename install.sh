#!/usr/bin/env bash
# install.sh — Installs the OpenCode Multi-Agent Pipeline
# Usage: curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/install.sh | bash
set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
AGENTS_DIR="$CONFIG_DIR/agents"
SCRIPTS_DIR="$CONFIG_DIR/scripts"
MANIFEST="$CONFIG_DIR/.opencode-pipeline-manifest.json"
BACKUP="$CONFIG_DIR/.opencode-pipeline-config-backup.json"
CONFIG_FILE="$CONFIG_DIR/opencode.json"
DEFAULT_STATE="$CONFIG_DIR/.opencode-pipeline-default-state.json"
GITIGNORE_MARKER="$CONFIG_DIR/.opencode-pipeline-gitignore-owned"
BIN_DIR="${HOME}/.local/bin"

AGENTS=("pipeline.md" "planner.md" "debater.md" "implementer.md" "reviewer.md" "security-reviewer.md" "tester.md" "linter.md" "commit-msg.md")
SCRIPTS=("select-models.sh" "auto-select-models.sh")
MODEL_FILES=("assign_models.py" "roles.json")

echo "==> Installing OpenCode Multi-Agent Pipeline"
echo "    Target: $CONFIG_DIR"
echo ""

mkdir -p "$AGENTS_DIR" "$SCRIPTS_DIR/models" "$BIN_DIR"

# 1. Download agent files
echo "==> Downloading agents..."
INSTALLED_FILES=""
for f in "${AGENTS[@]}"; do
  curl -fsSL "$REPO_URL/agents/$f" -o "$AGENTS_DIR/$f"
  INSTALLED_FILES="$INSTALLED_FILES\"$f\","
  echo "    ✓ agents/$f"
done
INSTALLED_FILES="[${INSTALLED_FILES%,}]"

# 2. Download scripts
echo "==> Downloading scripts..."
INSTALLED_SCRIPTS=""
for script in "${SCRIPTS[@]}"; do
  curl -fsSL "$REPO_URL/$script" -o "$SCRIPTS_DIR/$script"
  chmod +x "$SCRIPTS_DIR/$script"
  INSTALLED_SCRIPTS="$INSTALLED_SCRIPTS\"$script\","
  echo "    ✓ scripts/$script"
done
INSTALLED_SCRIPTS="[${INSTALLED_SCRIPTS%,}]"

# 3. Download model data files
echo "==> Downloading model data..."
for f in "${MODEL_FILES[@]}"; do
  curl -fsSL "$REPO_URL/models/$f" -o "$SCRIPTS_DIR/models/$f"
done
echo "    ✓ models/ (data files)"

# 4. Symlinks — currently none
echo "==> Symlinks (none needed)"

# 5. Merge default agent and reserve pipeline role agents for orchestrators
echo "==> Configuring pipeline permissions..."
python3 <<PYEOF
import json, os, shutil

config_file = "$CONFIG_FILE"
backup_file = "$BACKUP"
default_state_file = "$DEFAULT_STATE"
pipeline_agent_patterns = (
    'planner*', 'debater*', 'implementer*', 'reviewer*',
    'security-reviewer*', 'tester*', 'linter*', 'commit-msg*'
)

if os.path.exists(config_file):
    with open(config_file) as f:
        config = json.load(f)
    manifest_version = 0
    if os.path.exists("$MANIFEST"):
        with open("$MANIFEST") as f:
            manifest_version = json.load(f).get('version', 1)
    if not os.path.exists(backup_file) and manifest_version < 2 and not os.path.exists("$CONFIG_DIR/.opencode-pipeline-gpt-manifest.json"):
        shutil.copy2(config_file, backup_file)
        print('    backed up existing config')
else:
    config = {}

with open(default_state_file, 'w') as f:
    json.dump({'present': 'default_agent' in config, 'value': config.get('default_agent')}, f)
config['default_agent'] = 'pipeline'

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
    f.write('\n')

print('    default_agent set to pipeline')
print('    pipeline role agents reserved for pipeline orchestrators')
PYEOF

# 6. Write manifest
echo "==> Writing manifest..."
python3 <<PYEOF
import json, datetime, os

with open("$DEFAULT_STATE") as f:
    previous_default_agent = json.load(f)

manifest = {
    "version": 2,
    "installed_at": datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    "files": $INSTALLED_FILES,
    "scripts": $INSTALLED_SCRIPTS,
    "config_backup": "$BACKUP",
    "previous_default_agent": previous_default_agent
}

with open("$MANIFEST", 'w') as f:
    json.dump(manifest, f, indent=2)

os.remove("$DEFAULT_STATE")

print('    \u2713 manifest written')
PYEOF

# 7. Add state file to global gitignore
GITIGNORE="$CONFIG_DIR/.gitignore"
if ! grep -q 'opencode-workflow-state' "$GITIGNORE" 2>/dev/null; then
  echo ".opencode-workflow-state.md" >> "$GITIGNORE" 2>/dev/null || true
  touch "$GITIGNORE_MARKER"
  echo "==> Added .opencode-workflow-state.md to global gitignore"
fi

echo ""
echo "==> ✓ Pipeline installed!"
echo ""
echo "    Run 'opencode' in any project — pipeline is your default agent."
echo ""
echo "    To (re-)assign models:"
echo "      $SCRIPTS_DIR/auto-select-models.sh    (automatic, capability-scored)"
echo "      $SCRIPTS_DIR/select-models.sh          (interactive, fzf)"
echo ""
echo "    GPT variant available — install a paid pipeline alongside:"
echo "      curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/install-gpt.sh | bash"
echo "    Switch between free and GPT via Tab key in the opencode TUI."
echo ""
echo "    To uninstall:"
echo "      curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/uninstall.sh | bash"
