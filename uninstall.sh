#!/usr/bin/env bash
# uninstall.sh — Removes the OpenCode Multi-Agent Pipeline
# Usage: curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/uninstall.sh | bash
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
MANIFEST="$CONFIG_DIR/.opencode-pipeline-manifest.json"
BACKUP="$CONFIG_DIR/.opencode-pipeline-config-backup.json"
CONFIG_FILE="$CONFIG_DIR/opencode.json"
SCRIPTS_DIR="$CONFIG_DIR/scripts"
STATE_FILE="$CONFIG_DIR/.opencode-pipeline-fallback.json"
BIN_DIR="${HOME}/.local/bin"

echo "==> Uninstalling OpenCode Multi-Agent Pipeline"
echo ""

if [[ ! -f "$MANIFEST" ]]; then
  echo "    No manifest found — nothing to uninstall."
  exit 0
fi

# 1. Read manifest and remove agent files
echo "==> Removing agent files..."
python3 <<PYEOF
import json, os

with open("$MANIFEST") as f:
    manifest = json.load(f)

agents_dir = "$CONFIG_DIR/agents"
removed = 0
for fname in manifest.get("files", []):
    path = os.path.join(agents_dir, fname.split("/")[-1])
    if os.path.exists(path):
        os.remove(path)
        removed += 1
        print(f"    \u2717 {fname}")

if removed == 0:
    print("    (no agent files to remove)")
PYEOF

# 2. Remove scripts directory
if [[ -d "$SCRIPTS_DIR" ]]; then
  rm -rf "$SCRIPTS_DIR"
  echo "==> Removed scripts/ directory"
fi

# 3. Remove symlinks
for link in opencode-pipeline-fallback; do
  if [[ -L "$BIN_DIR/$link" ]]; then
    rm "$BIN_DIR/$link"
    echo "==> Removed symlink: $BIN_DIR/$link"
  fi
done

# 4. Remove fallback state (legacy)
if [[ -f "$STATE_FILE" ]]; then
  rm "$STATE_FILE"
  echo "==> Removed fallback state"
fi

# 5. Restore backed-up config then clean any remaining pipeline references
if [[ -f "$BACKUP" ]]; then
  cp "$BACKUP" "$CONFIG_FILE"
  rm "$BACKUP"
  echo "==> Restored original config from backup"
fi

# Always clean any remaining pipeline references from the config
if command -v python3 &>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
  python3 <<PYEOF
import json

with open("$CONFIG_FILE") as f:
    config = json.load(f)

changed = False

# Remove default_agent if it points to pipeline
if config.get('default_agent') == 'pipeline':
    del config['default_agent']
    changed = True

# Remove any explicit pipeline agent blocks
pipeline_agents = {"pipeline", "planner", "debater", "implementer", "reviewer", "tester", "linter", "commit-msg"}
agent_block = config.get('agent', {})
if isinstance(agent_block, dict):
    for name in list(agent_block.keys()):
        if name in pipeline_agents:
            del agent_block[name]
            changed = True
    if not agent_block:
        del config['agent']
        changed = True

if changed:
    with open("$CONFIG_FILE", 'w') as f:
        json.dump(config, f, indent=2)
        f.write('\n')
    print('    Cleaned pipeline references from config')
else:
    print('    Config already clean')
PYEOF
fi

# 6. Remove manifest
rm "$MANIFEST"
echo "==> Removed manifest"

# 7. Clean gitignore entry
GITIGNORE="$CONFIG_DIR/.gitignore"
if [[ -f "$GITIGNORE" ]]; then
  TMP=$(mktemp)
  grep -v '^\.opencode-workflow-state\.md$' "$GITIGNORE" > "$TMP" 2>/dev/null || true
  mv "$TMP" "$GITIGNORE"
  echo "==> Cleaned gitignore"
fi

echo ""
echo "==> \u2713 Pipeline uninstalled."
