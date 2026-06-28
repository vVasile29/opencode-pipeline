#!/usr/bin/env bash
# uninstall-gpt.sh — Removes GPT pipeline agents (leaves free pipeline intact)
# Usage: curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/uninstall-gpt.sh | bash
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
AGENTS_DIR="$CONFIG_DIR/agents"
MANIFEST="$CONFIG_DIR/.opencode-pipeline-gpt-manifest.json"
CONFIG_FILE="$CONFIG_DIR/opencode.json"

echo "==> Uninstalling GPT Pipeline"
echo ""

if [[ ! -f "$MANIFEST" ]]; then
  echo "    No GPT pipeline manifest found — nothing to uninstall."
  echo "    (The free pipeline at $AGENTS_DIR is untouched.)"
  exit 0
fi

# 1. Remove GPT agent files
echo "==> Removing GPT agent files..."
python3 <<PYEOF
import json, os

with open("$MANIFEST") as f:
    manifest = json.load(f)

agents_dir = "$AGENTS_DIR"
removed = 0
for fname in manifest.get("files", []):
    path = os.path.join(agents_dir, fname)
    if os.path.exists(path):
        os.remove(path)
        removed += 1
        print(f"    removed {fname}")

if removed == 0:
    print("    (no GPT agent files to remove)")
PYEOF

# 2. Remove manifest
rm "$MANIFEST"
echo "==> Removed GPT manifest"

# 3. If default_agent was pipeline-gpt, reset to pipeline
if command -v python3 &>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
  python3 <<PYEOF
import json

with open("$CONFIG_FILE") as f:
    config = json.load(f)

changed = False
if config.get('default_agent') == 'pipeline-gpt':
    config['default_agent'] = 'pipeline'
    changed = True
    print('    default_agent reset to pipeline')

if changed:
    with open("$CONFIG_FILE", 'w') as f:
        json.dump(config, f, indent=2)
        f.write('\n')
PYEOF
fi

echo ""
echo "==> ✓ GPT Pipeline uninstalled."
echo "    Free pipeline is still available. Run 'opencode' to use it."
