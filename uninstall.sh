#!/usr/bin/env bash
# uninstall.sh — Removes the OpenCode Multi-Agent Pipeline
# Usage: curl -fsSL https://raw.githubusercontent.com/YOUR_USER/opencode-pipeline/main/uninstall.sh | bash
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
MANIFEST="$CONFIG_DIR/.opencode-pipeline-manifest.json"
BACKUP="$CONFIG_DIR/.opencode-pipeline-config-backup.json"
CONFIG_FILE="$CONFIG_DIR/opencode.json"

echo "==> Uninstalling OpenCode Multi-Agent Pipeline"
echo ""

if [[ ! -f "$MANIFEST" ]]; then
  echo "    ⚠ No manifest found at $MANIFEST"
  echo "    Nothing to uninstall."
  exit 0
fi

# 1. Read manifest and remove agent files
echo "==> Removing agent files..."
python3 <<PYEOF
import json

with open("$MANIFEST") as f:
    manifest = json.load(f)

agents_dir = "$CONFIG_DIR/agents"
removed = 0
for fname in manifest.get("files", []):
    path = "$CONFIG_DIR/agents/" + fname.split("/")[-1]
    import os
    if os.path.exists(path):
        os.remove(path)
        removed += 1
        print(f"    ✗ {fname}")

if removed == 0:
    print("    (no agent files to remove)")
PYEOF

# 2. Restore backed-up config
if [[ -f "$BACKUP" ]]; then
  cp "$BACKUP" "$CONFIG_FILE"
  rm "$BACKUP"
  echo "==> Restored original config from backup"
else
  # Remove default_agent from config if no backup
  if command -v python3 &>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
    echo "==> Removing default_agent from config..."
    python3 <<PYEOF
import json

with open("$CONFIG_FILE") as f:
    config = json.load(f)

if config.get('default_agent') == 'pipeline':
    del config['default_agent']

with open("$CONFIG_FILE", 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')

print('    ✓ default_agent removed')
PYEOF
  fi
fi

# 3. Remove manifest
rm "$MANIFEST"
echo "==> Removed manifest"

# 4. Clean gitignore entry (gentle — only remove exact match)
GITIGNORE="$CONFIG_DIR/.gitignore"
if [[ -f "$GITIGNORE" ]]; then
  TMP=$(mktemp)
  grep -v '^\.opencode-workflow-state\.md$' "$GITIGNORE" > "$TMP" 2>/dev/null || true
  mv "$TMP" "$GITIGNORE"
  echo "==> Cleaned gitignore"
fi

echo ""
echo "==> ✓ Pipeline uninstalled."
