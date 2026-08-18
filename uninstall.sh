#!/usr/bin/env bash
# uninstall.sh — Removes the OpenCode Multi-Agent Pipeline
# Usage: curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/uninstall.sh | bash
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
MANIFEST="$CONFIG_DIR/.opencode-pipeline-manifest.json"
BACKUP="$CONFIG_DIR/.opencode-pipeline-config-backup.json"
CONFIG_FILE="$CONFIG_DIR/opencode.json"
GITIGNORE_MARKER="$CONFIG_DIR/.opencode-pipeline-gitignore-owned"
SCRIPTS_DIR="$CONFIG_DIR/scripts"
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

# 3. Clean pipeline-owned config while preserving unrelated changes
HAS_BACKUP=0
if [[ -f "$BACKUP" ]]; then
  HAS_BACKUP=1
fi

# Always clean any remaining pipeline references from the config
if command -v python3 &>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
  python3 <<PYEOF
import json
import os

with open("$CONFIG_FILE") as f:
    config = json.load(f)

changed = False
gpt_pipeline_installed = os.path.exists("$CONFIG_DIR/.opencode-pipeline-gpt-manifest.json")
original_config = {}
if $HAS_BACKUP:
    with open("$BACKUP") as f:
        original_config = json.load(f)

with open("$MANIFEST") as f:
    manifest = json.load(f)

# Restore the default that existed immediately before this pipeline changed it.
if config.get('default_agent') == 'pipeline':
    previous_default = manifest.get('previous_default_agent', {})
    if gpt_pipeline_installed and previous_default.get('present'):
        config['default_agent'] = previous_default.get('value')
    elif gpt_pipeline_installed:
        del config['default_agent']
    elif 'default_agent' in original_config:
        config['default_agent'] = original_config['default_agent']
    else:
        del config['default_agent']
    changed = True

# Remove inline blocks only for legacy manifests that may have installed them.
pipeline_agents = {"pipeline", "planner", "debater", "implementer", "reviewer", "security-reviewer", "tester", "linter", "commit-msg"}
pipeline_agent_patterns = (
    'planner*', 'debater*', 'implementer*', 'reviewer*',
    'security-reviewer*', 'tester*', 'linter*', 'commit-msg*'
)
agent_block = config.get('agent', {})
manifest_version = manifest.get('version', 1)
if manifest_version < 2 and isinstance(agent_block, dict):
    for name in list(agent_block.keys()):
        if name in pipeline_agents:
            del agent_block[name]
            changed = True
    if not agent_block and 'agent' in config:
        del config['agent']
        changed = True

# Keep shared role isolation while the GPT pipeline remains installed. When the
# final pipeline is removed, restore only managed rules from the original config.
permission = config.get('permission', {})
if gpt_pipeline_installed:
    if isinstance(permission, str):
        permission = {'*': permission}
    task = permission.get('task', {})
    if isinstance(task, str):
        task = {'*': task}
    for pattern in pipeline_agent_patterns:
        task.pop(pattern, None)
        task[pattern] = 'deny'
    permission['task'] = task
    config['permission'] = permission
    changed = True
elif isinstance(permission, dict):
    task = permission.get('task')
    if isinstance(task, dict):
        original_permission = original_config.get('permission', {})
        original_task = original_permission.get('task', {}) if isinstance(original_permission, dict) else {}
        managed_denies = {pattern for pattern in pipeline_agent_patterns if task.get(pattern) == 'deny'}
        if managed_denies:
            task = {key: value for key, value in task.items() if key not in managed_denies}
            if isinstance(original_task, dict):
                original_keys = list(original_task)
                for pattern in (key for key in original_keys if key in managed_denies):
                    items = list(task.items())
                    original_index = original_keys.index(pattern)
                    successor = next((key for key in original_keys[original_index + 1:] if key in task), None)
                    predecessor = next((key for key in reversed(original_keys[:original_index]) if key in task), None)
                    if successor is not None:
                        insert_at = next(i for i, (key, _) in enumerate(items) if key == successor)
                    elif predecessor is not None:
                        insert_at = next(i for i, (key, _) in enumerate(items) if key == predecessor) + 1
                    else:
                        insert_at = len(items)
                    items.insert(insert_at, (pattern, original_task[pattern]))
                    task = dict(items)
            changed = True
        if isinstance(original_task, str) and task == {'*': original_task}:
            permission['task'] = original_task
        elif task:
            permission['task'] = task
        else:
            del permission['task']
    original_permission = original_config.get('permission')
    if isinstance(original_permission, str) and permission == {'*': original_permission}:
        config['permission'] = original_permission
    elif permission:
        config['permission'] = permission
    else:
        config.pop('permission', None)

if changed:
    with open("$CONFIG_FILE", 'w') as f:
        json.dump(config, f, indent=2)
        f.write('\n')
    print('    Cleaned pipeline references from config')
else:
    print('    Config already clean')
PYEOF
fi

if [[ ! -f "$CONFIG_DIR/.opencode-pipeline-gpt-manifest.json" && -f "$BACKUP" ]]; then
  rm "$BACKUP"
  echo "==> Removed config backup"
fi

# 4. Remove manifest
rm "$MANIFEST"
echo "==> Removed manifest"

# 5. Clean gitignore entry when no pipeline remains
GITIGNORE="$CONFIG_DIR/.gitignore"
if [[ ! -f "$CONFIG_DIR/.opencode-pipeline-gpt-manifest.json" && -f "$GITIGNORE_MARKER" && -f "$GITIGNORE" ]]; then
  TMP=$(mktemp)
  grep -v '^\.opencode-workflow-state\.md$' "$GITIGNORE" > "$TMP" 2>/dev/null || true
  mv "$TMP" "$GITIGNORE"
  rm "$GITIGNORE_MARKER"
  echo "==> Cleaned gitignore"
fi

echo ""
echo "==> ✓ Pipeline uninstalled."
