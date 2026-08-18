#!/usr/bin/env bash
# uninstall-gpt.sh — Removes GPT pipeline agents (leaves free pipeline intact)
# Usage: curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/uninstall-gpt.sh | bash
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
AGENTS_DIR="$CONFIG_DIR/agents"
MANIFEST="$CONFIG_DIR/.opencode-pipeline-gpt-manifest.json"
BACKUP="$CONFIG_DIR/.opencode-pipeline-config-backup.json"
CONFIG_FILE="$CONFIG_DIR/opencode.json"
GITIGNORE_MARKER="$CONFIG_DIR/.opencode-pipeline-gitignore-owned"

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

# 3. Reset the default and remove GPT task deny rules
if command -v python3 &>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
  python3 <<PYEOF
import json
import os

with open("$CONFIG_FILE") as f:
    config = json.load(f)

changed = False
pipeline_agent_patterns = (
    'planner*', 'debater*', 'implementer*', 'reviewer*',
    'security-reviewer*', 'tester*', 'linter*', 'commit-msg*'
)
free_pipeline_installed = os.path.exists("$CONFIG_DIR/.opencode-pipeline-manifest.json")
original_config = {}
if os.path.exists("$BACKUP"):
    with open("$BACKUP") as f:
        original_config = json.load(f)
if config.get('default_agent') == 'pipeline-gpt':
    if free_pipeline_installed:
        config['default_agent'] = 'pipeline'
    elif 'default_agent' in original_config:
        config['default_agent'] = original_config['default_agent']
    else:
        del config['default_agent']
    changed = True
    print('    default_agent reset')

permission = config.get('permission', {})
if free_pipeline_installed:
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
    print('    Updated pipeline task permissions')
PYEOF
fi

if [[ ! -f "$CONFIG_DIR/.opencode-pipeline-manifest.json" && -f "$BACKUP" ]]; then
  rm "$BACKUP"
  echo "==> Removed config backup"
fi

# 4. Clean gitignore entry when no pipeline remains
GITIGNORE="$CONFIG_DIR/.gitignore"
if [[ ! -f "$CONFIG_DIR/.opencode-pipeline-manifest.json" && -f "$GITIGNORE_MARKER" && -f "$GITIGNORE" ]]; then
  TMP=$(mktemp)
  grep -v '^\.opencode-workflow-state\.md$' "$GITIGNORE" > "$TMP" 2>/dev/null || true
  mv "$TMP" "$GITIGNORE"
  rm "$GITIGNORE_MARKER"
  echo "==> Cleaned gitignore"
fi

echo ""
echo "==> ✓ GPT Pipeline uninstalled."
if [[ -f "$CONFIG_DIR/.opencode-pipeline-manifest.json" ]]; then
  echo "    Free pipeline is still available. Run 'opencode' to use it."
fi
