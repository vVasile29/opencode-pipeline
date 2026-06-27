#!/usr/bin/env bash
# install.sh — Installs the OpenCode Multi-Agent Pipeline
# Usage: curl -fsSL https://raw.githubusercontent.com/YOUR_USER/opencode-pipeline/main/install.sh | bash
set -euo pipefail

PIPELINE_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
AGENTS_DIR="$CONFIG_DIR/agents"
MANIFEST="$CONFIG_DIR/.opencode-pipeline-manifest.json"
BACKUP="$CONFIG_DIR/.opencode-pipeline-config-backup.json"
CONFIG_FILE="$CONFIG_DIR/opencode.json"

echo "==> Installing OpenCode Multi-Agent Pipeline"
echo "    Target: $CONFIG_DIR"
echo ""

mkdir -p "$AGENTS_DIR"

# 1. Copy agent files
echo "==> Copying agents..."
INSTALLED_FILES=""
for f in "$PIPELINE_DIR"/agents/*.md; do
  basename=$(basename "$f")
  cp "$f" "$AGENTS_DIR/$basename"
  INSTALLED_FILES="$INSTALLED_FILES\"$basename\","
  echo "    ✓ agents/$basename"
done
INSTALLED_FILES="[${INSTALLED_FILES%,}]"

# 2. Backup existing config
if [[ -f "$CONFIG_FILE" ]]; then
  cp "$CONFIG_FILE" "$BACKUP"
  echo "==> Backed up existing config → $(basename "$BACKUP")"
fi

# 3. Merge default_agent into opencode.json (pure python3)
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

print('    ✓ default_agent set to pipeline')
PYEOF

# 4. Write manifest
echo "==> Writing manifest..."
python3 <<PYEOF
import json, datetime

manifest = {
    "version": 1,
    "installed_at": datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    "files": $INSTALLED_FILES,
    "config_backup": "$BACKUP"
}

with open("$MANIFEST", 'w') as f:
    json.dump(manifest, f, indent=2)

print('    ✓ manifest written')
PYEOF

# 5. Add state file to global gitignore
GITIGNORE="$CONFIG_DIR/.gitignore"
if ! grep -q 'opencode-workflow-state' "$GITIGNORE" 2>/dev/null; then
  echo ".opencode-workflow-state.md" >> "$GITIGNORE" 2>/dev/null || true
  echo "==> Added .opencode-workflow-state.md to global gitignore"
fi

echo ""
echo "==> ✓ Pipeline installed!"
echo "    Run 'opencode' in any project — pipeline is your default agent."
echo ""
echo "    To swap models:   curl -fsSL https://raw.githubusercontent.com/YOUR_USER/opencode-pipeline/main/select-models.sh | bash"
echo "    To uninstall:     curl -fsSL https://raw.githubusercontent.com/YOUR_USER/opencode-pipeline/main/uninstall.sh | bash"
