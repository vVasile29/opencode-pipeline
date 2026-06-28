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

# 5. Backup existing config
if [[ -f "$CONFIG_FILE" ]]; then
  cp "$CONFIG_FILE" "$BACKUP"
  echo "==> Backed up existing config → $(basename "$BACKUP")"
fi

# 6. Merge default_agent into opencode.json
echo "==> Setting default_agent to 'pipeline'..."
python3 <<PYEOF
import json, os

config_file = "$CONFIG_FILE"

if os.path.exists(config_file):
    with open(config_file) as f:
        config = json.load(f)
else:
    config = {}

config['default_agent'] = 'pipeline'

with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')

print('    default_agent set to pipeline')
PYEOF

# 7. Write manifest
echo "==> Writing manifest..."
python3 <<PYEOF
import json, datetime

manifest = {
    "version": 1,
    "installed_at": datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    "files": $INSTALLED_FILES,
    "scripts": $INSTALLED_SCRIPTS,
    "config_backup": "$BACKUP"
}

with open("$MANIFEST", 'w') as f:
    json.dump(manifest, f, indent=2)

print('    \u2713 manifest written')
PYEOF

# 8. Add state file to global gitignore
GITIGNORE="$CONFIG_DIR/.gitignore"
if ! grep -q 'opencode-workflow-state' "$GITIGNORE" 2>/dev/null; then
  echo ".opencode-workflow-state.md" >> "$GITIGNORE" 2>/dev/null || true
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
